"""Posts a stage's result (success or failure) back to the AWS callback endpoint
that resumes the Step Functions task-token wait.
"""
import os
import time

import requests

CALLBACK_SHARED_SECRET = os.environ.get("CALLBACK_SHARED_SECRET", "")


def post_callback(callback_url: str, payload: dict, retries: int = 3, timeout_s: int = 15) -> None:
    headers = {
        "X-Callback-Secret": CALLBACK_SHARED_SECRET,
        "Content-Type": "application/json",
    }
    last_exc = None
    for attempt in range(retries):
        try:
            resp = requests.post(callback_url, json=payload, headers=headers, timeout=timeout_s)
            resp.raise_for_status()
            return
        except requests.RequestException as exc:
            last_exc = exc
            time.sleep(min(2 ** attempt, 8))
    raise RuntimeError(f"Failed to deliver callback to {callback_url} after {retries} attempts") from last_exc
