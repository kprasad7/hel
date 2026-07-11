"""Receives RunPod's job-completion webhook and resumes the Step Functions
execution that is parked at a waitForTaskToken state for this stage.
"""
import json
import os

import boto3
from botocore.exceptions import ClientError

from common.dynamo import put_profile
from common.remote_write import push_metrics

CALLBACK_SECRET_NAME = os.environ["CALLBACK_SECRET_NAME"]
GRAFANA_REMOTE_WRITE_URL = os.environ.get("GRAFANA_REMOTE_WRITE_URL", "")
GRAFANA_REMOTE_WRITE_USER = os.environ.get("GRAFANA_REMOTE_WRITE_USER", "")
GRAFANA_API_KEY_SECRET_NAME = os.environ.get("GRAFANA_API_KEY_SECRET_NAME", "")

_sfn = boto3.client("stepfunctions")
_secrets = boto3.client("secretsmanager")

_cached_secret = None
_cached_grafana_api_key = None


def _expected_secret() -> str:
    global _cached_secret
    if _cached_secret is None:
        _cached_secret = _secrets.get_secret_value(SecretId=CALLBACK_SECRET_NAME)["SecretString"]
    return _cached_secret


def _grafana_api_key() -> str:
    global _cached_grafana_api_key
    if _cached_grafana_api_key is None:
        _cached_grafana_api_key = _secrets.get_secret_value(SecretId=GRAFANA_API_KEY_SECRET_NAME)["SecretString"]
    return _cached_grafana_api_key


def _push_profiling_metrics(job_id: str, stage: str, profiling: dict) -> None:
    # Best-effort: a metrics-push failure must never block the pipeline.
    if not GRAFANA_REMOTE_WRITE_URL:
        return
    try:
        gpu = profiling.get("gpu") or {}
        util_samples = gpu.get("utilization_pct_samples") or []
        mem_samples = gpu.get("memory_used_mb_samples") or []
        power_samples = gpu.get("power_watts_samples") or []

        push_metrics(
            remote_write_url=GRAFANA_REMOTE_WRITE_URL,
            username=GRAFANA_REMOTE_WRITE_USER,
            api_key=_grafana_api_key(),
            metric_prefix="vidplatform_gpu",
            base_labels={"job_id": job_id, "stage": stage, "device": gpu.get("device", "unknown")},
            gauges={
                "cold_start": 1 if profiling.get("cold_start") else 0,
                "model_load_ms": profiling.get("model_load_ms"),
                "preprocess_ms": profiling.get("preprocess_ms"),
                "inference_ms": profiling.get("inference_ms"),
                "postprocess_upload_ms": profiling.get("postprocess_upload_ms"),
                "utilization_pct_avg": _avg(util_samples),
                "memory_used_mb_max": max(mem_samples) if mem_samples else None,
                "power_watts_avg": _avg(power_samples),
            },
        )
    except Exception:
        # Swallow — profiling metrics are an optimization aid, not correctness.
        pass


def _avg(values: list):
    return sum(values) / len(values) if values else None


def handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if headers.get("x-callback-secret") != _expected_secret():
        return _response(403, {"error": "forbidden"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "invalid JSON body"})

    task_token = body.get("task_token")
    status = body.get("status")
    stage = body.get("stage")
    if not task_token or status not in ("SUCCESS", "FAILURE"):
        return _response(400, {"error": "missing task_token or invalid status"})

    job_id = _job_id_from_request(event) or body.get("job_id")

    try:
        if status == "SUCCESS":
            profiling = body.get("profiling")
            if profiling and job_id:
                put_profile(job_id, stage, profiling)
                _push_profiling_metrics(job_id, stage, profiling)
            _sfn.send_task_success(
                taskToken=task_token,
                output=json.dumps({"stage": stage, "output_key": body.get("output_key")}),
            )
        else:
            _sfn.send_task_failure(
                taskToken=task_token,
                error="WorkerFailure",
                cause=json.dumps({"error": body.get("error"), "stage": stage})[:32000],
            )
    except ClientError as exc:
        # Task token already consumed/expired (e.g. Step Functions already timed
        # out this state) — treat as a delivered-but-stale callback, not a retry.
        return _response(410, {"error": f"task token no longer valid: {exc}"})

    return _response(200, {"ok": True})


def _job_id_from_request(event):
    return (event.get("pathParameters") or {}).get("job_id") or (event.get("queryStringParameters") or {}).get("job_id")


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
