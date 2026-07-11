"""RunPod serverless handler for the TTS narration stage (Kokoro-82M).

Job input contract (set by services/invoke_tts):
{
  "text": str,             # narration script — v1 reuses the same prompt used
                            # for video_gen; a separate script field can be
                            # added later if the UI grows one.
  "voice": str (optional, default "af_heart"),
  "upload_url": str,       # presigned S3 PUT URL for the output wav
  "output_key": str,
  "callback_url": str,
  "task_token": str,
}
"""
import os
import time
import traceback

import numpy as np
import runpod
import soundfile as sf

from common.callback import post_callback
from common.profiling import GpuProfiler, StageTimer
from common.s3_upload import upload_to_presigned_url

LANG_CODE = os.environ.get("LANG_CODE", "a")  # "a" = American English
SAMPLE_RATE = 24000

_pipeline = None
_model_load_ms = None


def _load_model() -> None:
    global _pipeline, _model_load_ms
    start = time.perf_counter()
    from kokoro import KPipeline

    _pipeline = KPipeline(lang_code=LANG_CODE)
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
        text = job_input["text"]
        voice = job_input.get("voice", "af_heart")
        upload_url = job_input["upload_url"]

        with GpuProfiler() as profiler:
            with timer.measure("inference_ms"):
                chunks = []
                for _graphemes, _phonemes, audio in _pipeline(text, voice=voice):
                    chunks.append(audio)
                full_audio = np.concatenate(chunks) if chunks else np.zeros(0, dtype=np.float32)

            with timer.measure("postprocess_upload_ms"):
                local_path = "/tmp/output.wav"
                sf.write(local_path, full_audio, SAMPLE_RATE)
                upload_to_presigned_url(local_path, upload_url, "audio/wav")

        profiling_payload = {
            "stage": "tts",
            "cold_start": is_cold_start,
            "model_load_ms": cold_start_ms,
            "preprocess_ms": 0,
            "inference_ms": timer.timings_ms.get("inference_ms", 0),
            "postprocess_upload_ms": timer.timings_ms.get("postprocess_upload_ms", 0),
            "gpu": profiler.summary(),
            "input_params": {"voice": voice, "duration_s": round(len(full_audio) / SAMPLE_RATE, 2)},
        }

        post_callback(callback_url, {
            "task_token": task_token,
            "status": "SUCCESS",
            "stage": "tts",
            "output_key": job_input.get("output_key"),
            "profiling": profiling_payload,
        })
        return {"status": "SUCCESS"}

    except Exception as exc:
        post_callback(callback_url, {
            "task_token": task_token,
            "status": "FAILURE",
            "stage": "tts",
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })
        raise


runpod.serverless.start({"handler": handler})
