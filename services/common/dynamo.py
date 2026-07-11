"""DynamoDB access for the single-table job/profiling design.

PK "JOB#<job_id>", SK "META"            -> job status/params/output
PK "JOB#<job_id>", SK "PROFILE#<stage>" -> per-stage GPU profiling record
"""
import os
import time

import boto3

_TABLE_NAME = os.environ.get("JOBS_TABLE")
_dynamodb = boto3.resource("dynamodb")


def _table():
    return _dynamodb.Table(_TABLE_NAME)


def put_job(job_id: str, prompt: str, params: dict) -> None:
    now = int(time.time())
    _table().put_item(Item={
        "PK": f"JOB#{job_id}",
        "SK": "META",
        "job_id": job_id,
        "status": "PENDING",
        "stage": "SUBMITTED",
        "prompt": prompt,
        "params": params,
        "created_at": now,
        "updated_at": now,
    })


def get_job(job_id: str):
    resp = _table().get_item(Key={"PK": f"JOB#{job_id}", "SK": "META"})
    return resp.get("Item")


def update_job_status(
    job_id: str,
    status: str,
    stage: str = None,
    output_url: str = None,
    error: str = None,
    extra_fields: dict = None,
) -> None:
    update_expr = ["#status = :status", "updated_at = :updated_at"]
    expr_names = {"#status": "status"}
    expr_values = {":status": status, ":updated_at": int(time.time())}

    if stage is not None:
        update_expr.append("stage = :stage")
        expr_values[":stage"] = stage
    if output_url is not None:
        update_expr.append("output_url = :output_url")
        expr_values[":output_url"] = output_url
    if error is not None:
        update_expr.append("#error = :error")
        expr_names["#error"] = "error"
        expr_values[":error"] = error
    for key, value in (extra_fields or {}).items():
        if value is None:
            continue
        # Aliased via ExpressionAttributeNames since caller-supplied field names
        # (e.g. from a stage name) could collide with DynamoDB reserved words.
        name_alias = f"#{key}"
        update_expr.append(f"{name_alias} = :{key}")
        expr_names[name_alias] = key
        expr_values[f":{key}"] = value

    _table().update_item(
        Key={"PK": f"JOB#{job_id}", "SK": "META"},
        UpdateExpression="SET " + ", ".join(update_expr),
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
    )


def put_profile(job_id: str, stage: str, profiling: dict) -> None:
    _table().put_item(Item={
        "PK": f"JOB#{job_id}",
        "SK": f"PROFILE#{stage}",
        "job_id": job_id,
        "stage": stage,
        "profiling": profiling,
        "recorded_at": int(time.time()),
    })
