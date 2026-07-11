"""Fargate task: mixes background music/SFX into the lip-synced video's audio
track and writes the final assembled video. Runs fully inside AWS (unlike the
RunPod workers), so it talks to S3/DynamoDB directly via its task IAM role —
no presigned URLs or callback/webhook plumbing needed, unlike the RunPod
stages. This is also why it marks the job COMPLETE/FAILED itself (see
CLAUDE.md) instead of routing through a Step Functions "UpdateJobComplete"
Lambda the way the RunPod-invoking stages do.

Env vars (set per-execution by the Step Functions ContainerOverrides):
  JOB_ID, LIP_SYNC_KEY, BG_AUDIO_KEY, OUTPUT_KEY,
  ARTIFACTS_BUCKET, ARTIFACTS_BUCKET_DOMAIN, JOBS_TABLE
"""
import os
import subprocess
import time

import boto3

from common.dynamo import put_profile, update_job_status
from common.models import JobStatus

ARTIFACTS_BUCKET = os.environ["ARTIFACTS_BUCKET"]
ARTIFACTS_BUCKET_DOMAIN = os.environ["ARTIFACTS_BUCKET_DOMAIN"]
JOB_ID = os.environ["JOB_ID"]
LIP_SYNC_KEY = os.environ["LIP_SYNC_KEY"]
BG_AUDIO_KEY = os.environ["BG_AUDIO_KEY"]
OUTPUT_KEY = os.environ["OUTPUT_KEY"]

_s3 = boto3.client("s3")


def main() -> None:
    timings = {}
    start = time.perf_counter()

    video_path = "/tmp/lip_synced.mp4"
    audio_path = "/tmp/bg_audio.wav"
    output_path = "/tmp/final.mp4"

    t0 = time.perf_counter()
    _s3.download_file(ARTIFACTS_BUCKET, LIP_SYNC_KEY, video_path)
    _s3.download_file(ARTIFACTS_BUCKET, BG_AUDIO_KEY, audio_path)
    timings["download_ms"] = round((time.perf_counter() - t0) * 1000, 2)

    # Mixes bg music (quieter, weight 0.4) under the lip-synced video's existing
    # narration track (weight 1.0); duration=first trims/pads to the video's
    # length since bg_audio's generated duration won't exactly match.
    t0 = time.perf_counter()
    subprocess.run(
        [
            "ffmpeg", "-y",
            "-i", video_path,
            "-i", audio_path,
            "-filter_complex",
            "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=2:weights=1 0.4[aout]",
            "-map", "0:v",
            "-map", "[aout]",
            "-c:v", "copy",
            "-shortest",
            output_path,
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=280,
    )
    timings["mix_ms"] = round((time.perf_counter() - t0) * 1000, 2)

    t0 = time.perf_counter()
    _s3.upload_file(output_path, ARTIFACTS_BUCKET, OUTPUT_KEY, ExtraArgs={"ContentType": "video/mp4"})
    timings["upload_ms"] = round((time.perf_counter() - t0) * 1000, 2)

    put_profile(JOB_ID, "assembly", {
        "stage": "assembly",
        "cold_start": False,
        "model_load_ms": 0,
        "preprocess_ms": timings["download_ms"],
        "inference_ms": timings["mix_ms"],
        "postprocess_upload_ms": timings["upload_ms"],
        "gpu": {
            "device": "none (CPU-only Fargate task)",
            "utilization_pct_samples": [],
            "memory_used_mb_samples": [],
            "power_watts_samples": [],
        },
        "input_params": {},
    })

    output_url = f"https://{ARTIFACTS_BUCKET_DOMAIN}/{OUTPUT_KEY}"
    update_job_status(JOB_ID, JobStatus.COMPLETE, stage="DONE", output_url=output_url)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        update_job_status(
            JOB_ID, JobStatus.FAILED, stage="FAILED",
            error=f"ffmpeg failed: {(exc.stderr or '')[-2000:]}",
        )
        raise
    except Exception as exc:
        update_job_status(JOB_ID, JobStatus.FAILED, stage="FAILED", error=str(exc)[:2000])
        raise
