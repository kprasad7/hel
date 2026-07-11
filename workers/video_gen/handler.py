"""RunPod serverless handler for the text-to-video stage (LTX-Video).

Job input contract (set by services/orchestration's invoke_video_gen Lambda):
{
  "prompt": str,
  "width": int (optional, default 768),
  "height": int (optional, default 512),
  "num_frames": int (optional, default 121  # ~5s @ 24fps),
  "upload_url": str,      # presigned S3 PUT URL for the output mp4
  "output_key": str,      # the S3 key the upload_url points at (echoed back)
  "callback_url": str,    # API Gateway endpoint that resumes Step Functions
  "task_token": str,      # Step Functions waitForTaskToken token
}
"""
import os
import time
import traceback

import runpod
import torch

from common.callback import post_callback
from common.profiling import GpuProfiler, StageTimer
from common.s3_upload import upload_to_presigned_url

MODEL_ID = os.environ.get("MODEL_ID", "Lightricks/LTX-Video")

_pipe = None
_model_load_ms = None


def _load_model() -> None:
    global _pipe, _model_load_ms
    start = time.perf_counter()
    from diffusers import LTXPipeline

    pipe = LTXPipeline.from_pretrained(MODEL_ID, torch_dtype=torch.bfloat16)
    pipe.to("cuda")
    _pipe = pipe
    _model_load_ms = round((time.perf_counter() - start) * 1000, 2)


# Runs once at container start (cold start), not per-request.
_load_model()


def handler(job: dict) -> dict:
    global _model_load_ms

    job_input = job["input"]
    callback_url = job_input["callback_url"]
    task_token = job_input["task_token"]
    is_cold_start = _model_load_ms is not None
    cold_start_ms = _model_load_ms or 0
    # Only the first request after container start counts as a cold start.
    _model_load_ms = None

    timer = StageTimer()

    try:
        prompt = job_input["prompt"]
        width = job_input.get("width", 768)
        height = job_input.get("height", 512)
        num_frames = job_input.get("num_frames", 121)
        upload_url = job_input["upload_url"]

        with GpuProfiler() as profiler:
            with timer.measure("inference_ms"):
                frames = _pipe(
                    prompt=prompt,
                    width=width,
                    height=height,
                    num_frames=num_frames,
                ).frames[0]

            with timer.measure("postprocess_upload_ms"):
                local_path = "/tmp/output.mp4"
                _export_video(frames, local_path)
                upload_to_presigned_url(local_path, upload_url, "video/mp4")

        profiling_payload = {
            "stage": "video_gen",
            "cold_start": is_cold_start,
            "model_load_ms": cold_start_ms,
            "preprocess_ms": 0,
            "inference_ms": timer.timings_ms.get("inference_ms", 0),
            "postprocess_upload_ms": timer.timings_ms.get("postprocess_upload_ms", 0),
            "gpu": profiler.summary(),
            "input_params": {"width": width, "height": height, "num_frames": num_frames},
        }

        post_callback(callback_url, {
            "task_token": task_token,
            "status": "SUCCESS",
            "stage": "video_gen",
            "output_key": job_input.get("output_key"),
            "profiling": profiling_payload,
        })
        return {"status": "SUCCESS"}

    except Exception as exc:
        post_callback(callback_url, {
            "task_token": task_token,
            "status": "FAILURE",
            "stage": "video_gen",
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })
        raise


def _export_video(frames, path: str) -> None:
    from diffusers.utils import export_to_video
    export_to_video(frames, path, fps=24)


runpod.serverless.start({"handler": handler})
