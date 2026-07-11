from common.dynamo import update_job_status
from common.models import JobStatus


def handler(event, context):
    job_id = event["job_id"]
    error = event.get("error", {})
    update_job_status(job_id, JobStatus.FAILED, stage="FAILED", error=str(error)[:2000])
    return {"job_id": job_id, "status": JobStatus.FAILED}
