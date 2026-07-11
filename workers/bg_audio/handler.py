"""RunPod serverless handler for the background music/SFX stage (Stable Audio Open).

Job input contract (set by services/invoke_bg_audio):
{
  "prompt": str,            # e.g. "ambient electronic music, calm, cinematic"
  "duration_s": float (optional, default 10.0),
  "upload_url": str,        # presigned S3 PUT URL for the output wav
  "output_key": str,
  "callback_url": str,
  "task_token": str,
}
"""
import os
import time
import traceback

import runpod
import soundfile as sf
import torch

from common.callback import post_callback
from common.profiling import GpuProfiler, StageTimer
from common.s3_upload import upload_to_presigned_url

MODEL_ID = os.environ.get("MODEL_ID", "stabilityai/stable-audio-open-1.0")
NEGATIVE_PROMPT = "Low quality, distorted, clipping"

_pipe = None
_model_load_ms = None


def _load_model() -> None:
    global _pipe, _model_load_ms
    start = time.perf_counter()
    from diffusers import StableAudioPipeline

    pipe = StableAudioPipeline.from_pretrained(MODEL_ID, torch_dtype=torch.float16)
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
    _model_load_ms = None

    timer = StageTimer()

    try:
        prompt = job_input["prompt"]
        duration_s = job_input.get("duration_s", 10.0)
        upload_url = job_input["upload_url"]

        with GpuProfiler() as profiler:
            with timer.measure("inference_ms"):
                result = _pipe(
                    prompt=prompt,
                    negative_prompt=NEGATIVE_PROMPT,
                    num_inference_steps=200,
                    audio_end_in_s=duration_s,
                    num_waveforms_per_prompt=1,
                ).audios

            with timer.measure("postprocess_upload_ms"):
                local_path = "/tmp/output.wav"
                audio = result[0].T.float().cpu().numpy()
                sf.write(local_path, audio, _pipe.vae.sampling_rate)
                upload_to_presigned_url(local_path, upload_url, "audio/wav")

        profiling_payload = {
            "stage": "bg_audio",
            "cold_start": is_cold_start,
            "model_load_ms": cold_start_ms,
            "preprocess_ms": 0,
            "inference_ms": timer.timings_ms.get("inference_ms", 0),
            "postprocess_upload_ms": timer.timings_ms.get("postprocess_upload_ms", 0),
            "gpu": profiler.summary(),
            "input_params": {"duration_s": duration_s},
        }

        post_callback(callback_url, {
            "task_token": task_token,
            "status": "SUCCESS",
            "stage": "bg_audio",
            "output_key": job_input.get("output_key"),
            "profiling": profiling_payload,
        })
        return {"status": "SUCCESS"}

    except Exception as exc:
        post_callback(callback_url, {
            "task_token": task_token,
            "status": "FAILURE",
            "stage": "bg_audio",
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })
        raise


runpod.serverless.start({"handler": handler})
