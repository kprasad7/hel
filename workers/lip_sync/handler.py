"""RunPod serverless handler for the lip-sync stage (MuseTalk v1.5).

Job input contract (set by services/invoke_lip_sync):
{
  "video_url": str,   # presigned S3 GET URL for the video_gen stage output
  "audio_url": str,   # presigned S3 GET URL for the tts stage output
  "upload_url": str,  # presigned S3 PUT URL for this stage's output mp4
  "output_key": str,
  "callback_url": str,
  "task_token": str,
}

Unlike the other workers, MuseTalk isn't imported as a persistent in-process
model — its repo is a CLI script (`scripts.inference`) that loads the UNet,
VAE, Whisper, and face-parsing models fresh on every invocation. That means
this stage does NOT benefit from RunPod keeping a worker warm the way
video_gen/tts/bg_audio do: every request pays full model-load cost, not just
the first one after idle. `cold_start` is therefore always reported `true`
here, and `model_load_ms` isn't separated from `inference_ms` (the subprocess
doesn't expose that boundary without parsing its logs). This is a known,
flagged optimization gap — see CLAUDE.md — not an oversight; fixing it means
importing MuseTalk's internals directly instead of shelling out, which is a
bigger, riskier change to make without hands-on testing against their
current internal API.
"""
import os
import subprocess
import time
import traceback

import requests
import runpod
import yaml

from common.callback import post_callback
from common.profiling import GpuProfiler, StageTimer
from common.s3_upload import upload_to_presigned_url

MUSETALK_DIR = "/app/MuseTalk"
UNET_MODEL_PATH = f"{MUSETALK_DIR}/models/musetalkV15/unet.pth"
UNET_CONFIG = f"{MUSETALK_DIR}/models/musetalkV15/musetalk.json"


def _download(url: str, local_path: str) -> None:
    with requests.get(url, stream=True, timeout=120) as resp:
        resp.raise_for_status()
        with open(local_path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=1024 * 1024):
                f.write(chunk)


def handler(job: dict) -> dict:
    job_input = job["input"]
    callback_url = job_input["callback_url"]
    task_token = job_input["task_token"]

    timer = StageTimer()

    try:
        video_url = job_input["video_url"]
        audio_url = job_input["audio_url"]
        upload_url = job_input["upload_url"]

        video_path = "/tmp/input_video.mp4"
        audio_path = "/tmp/input_audio.wav"
        result_dir = "/tmp/results"
        result_name = "output.mp4"

        with timer.measure("preprocess_ms"):
            _download(video_url, video_path)
            _download(audio_url, audio_path)

            config_path = "/tmp/task.yaml"
            with open(config_path, "w") as f:
                yaml.safe_dump({
                    "task_0": {
                        "video_path": video_path,
                        "audio_path": audio_path,
                        "result_name": result_name,
                    }
                }, f)

        with GpuProfiler() as profiler:
            with timer.measure("inference_ms"):
                subprocess.run(
                    [
                        "python3", "-m", "scripts.inference",
                        "--inference_config", config_path,
                        "--result_dir", result_dir,
                        "--unet_model_path", UNET_MODEL_PATH,
                        "--unet_config", UNET_CONFIG,
                        "--version", "v15",
                    ],
                    cwd=MUSETALK_DIR,
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=280,
                )

            with timer.measure("postprocess_upload_ms"):
                output_path = os.path.join(result_dir, "v15", result_name)
                upload_to_presigned_url(output_path, upload_url, "video/mp4")

        profiling_payload = {
            "stage": "lip_sync",
            "cold_start": True,  # see module docstring — always true for this stage
            "model_load_ms": 0,  # not separable from inference_ms here
            "preprocess_ms": timer.timings_ms.get("preprocess_ms", 0),
            "inference_ms": timer.timings_ms.get("inference_ms", 0),
            "postprocess_upload_ms": timer.timings_ms.get("postprocess_upload_ms", 0),
            "gpu": profiler.summary(),
            "input_params": {},
        }

        post_callback(callback_url, {
            "task_token": task_token,
            "status": "SUCCESS",
            "stage": "lip_sync",
            "output_key": job_input.get("output_key"),
            "profiling": profiling_payload,
        })
        return {"status": "SUCCESS"}

    except subprocess.CalledProcessError as exc:
        post_callback(callback_url, {
            "task_token": task_token,
            "status": "FAILURE",
            "stage": "lip_sync",
            "error": f"MuseTalk inference failed: {exc}",
            "traceback": (exc.stderr or "")[-4000:],
        })
        raise
    except Exception as exc:
        post_callback(callback_url, {
            "task_token": task_token,
            "status": "FAILURE",
            "stage": "lip_sync",
            "error": str(exc),
            "traceback": traceback.format_exc(),
        })
        raise


runpod.serverless.start({"handler": handler})
