import json

from common.dynamo import get_job


def handler(event, context):
    job_id = (event.get("pathParameters") or {}).get("id")
    if not job_id:
        return _response(400, {"error": "missing job id"})

    job = get_job(job_id)
    if not job:
        return _response(404, {"error": "job not found"})

    return _response(200, {
        "job_id": job["job_id"],
        "status": job["status"],
        "stage": job.get("stage"),
        "output_url": job.get("output_url"),
        "bg_audio_url": job.get("bg_audio_url"),
        "error": job.get("error"),
    })


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
