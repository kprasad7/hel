import json
import os
import uuid

import boto3

from common.dynamo import put_job
from common.models import JobStatus

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
_sfn = boto3.client("stepfunctions")


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "invalid JSON body"})

    prompt = body.get("prompt")
    if not prompt or not isinstance(prompt, str):
        return _response(400, {"error": "'prompt' is required"})

    params = {
        "width": body.get("width", 768),
        "height": body.get("height", 512),
        "num_frames": body.get("num_frames", 121),
    }

    job_id = str(uuid.uuid4())
    put_job(job_id, prompt, params)

    _sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        name=job_id,
        input=json.dumps({"job_id": job_id, "prompt": prompt, "params": params}),
    )

    return _response(202, {"job_id": job_id, "status": JobStatus.PENDING})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
