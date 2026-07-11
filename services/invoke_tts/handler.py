"""Step Functions task (waitForTaskToken) that submits the TTS narration job
to RunPod. v1 reuses the video prompt as the narration script — the UI/API
doesn't expose a separate narration field yet (see CLAUDE.md).
"""
import json
import os
import urllib.request

import boto3

RUNPOD_ENDPOINT_ID = os.environ["RUNPOD_ENDPOINT_ID"]
RUNPOD_API_KEY_SECRET_NAME = os.environ["RUNPOD_API_KEY_SECRET_NAME"]
ARTIFACTS_BUCKET = os.environ["ARTIFACTS_BUCKET"]
API_INVOKE_URL = os.environ["API_INVOKE_URL"]
STAGE_NAME = "tts"

_secrets = boto3.client("secretsmanager")
_s3 = boto3.client("s3")

_cached_api_key = None


def _runpod_api_key() -> str:
    global _cached_api_key
    if _cached_api_key is None:
        _cached_api_key = _secrets.get_secret_value(SecretId=RUNPOD_API_KEY_SECRET_NAME)["SecretString"]
    return _cached_api_key


def handler(event, context):
    job_id = event["job_id"]
    prompt = event["prompt"]
    task_token = event["task_token"]

    output_key = f"{job_id}/{STAGE_NAME}/output.wav"
    upload_url = _s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": ARTIFACTS_BUCKET, "Key": output_key, "ContentType": "audio/wav"},
        ExpiresIn=900,
    )
    callback_url = f"{API_INVOKE_URL}/internal/runpod-callback/{STAGE_NAME}?job_id={job_id}"

    payload = {
        "input": {
            "text": prompt,
            "upload_url": upload_url,
            "output_key": output_key,
            "callback_url": callback_url,
            "task_token": task_token,
        }
    }

    req = urllib.request.Request(
        f"https://api.runpod.ai/v2/{RUNPOD_ENDPOINT_ID}/run",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {_runpod_api_key()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        if resp.status >= 300:
            raise RuntimeError(f"RunPod submit failed: HTTP {resp.status}")
