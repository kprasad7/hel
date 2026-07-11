"""Uploads a local artifact to S3 via a presigned PUT URL supplied by the
submitting Lambda. Workers never hold AWS credentials directly.
"""
import requests


def upload_to_presigned_url(local_path: str, presigned_put_url: str, content_type: str) -> None:
    with open(local_path, "rb") as f:
        resp = requests.put(
            presigned_put_url,
            data=f,
            headers={"Content-Type": content_type},
            timeout=120,
        )
        resp.raise_for_status()
