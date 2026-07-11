data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- invoke_* (one per parallel RunPod stage) ----------
module "invoke_video_gen" {
  source = "../invoke_worker"

  project      = var.project
  env          = var.env
  stage_name   = "video_gen"
  services_dir = var.services_dir

  runpod_endpoint_id         = var.runpod_video_gen_endpoint_id
  runpod_api_key_secret_arn  = var.runpod_api_key_secret_arn
  runpod_api_key_secret_name = var.runpod_api_key_secret_name
  artifacts_bucket_name      = var.artifacts_bucket_name
  artifacts_bucket_arn       = var.artifacts_bucket_arn
  api_invoke_url             = var.api_invoke_url
  timeout_seconds            = 300
}

module "invoke_tts" {
  source = "../invoke_worker"

  project      = var.project
  env          = var.env
  stage_name   = "tts"
  services_dir = var.services_dir

  runpod_endpoint_id         = var.runpod_tts_endpoint_id
  runpod_api_key_secret_arn  = var.runpod_api_key_secret_arn
  runpod_api_key_secret_name = var.runpod_api_key_secret_name
  artifacts_bucket_name      = var.artifacts_bucket_name
  artifacts_bucket_arn       = var.artifacts_bucket_arn
  api_invoke_url             = var.api_invoke_url
  timeout_seconds            = 180
}

module "invoke_bg_audio" {
  source = "../invoke_worker"

  project      = var.project
  env          = var.env
  stage_name   = "bg_audio"
  services_dir = var.services_dir

  runpod_endpoint_id         = var.runpod_bg_audio_endpoint_id
  runpod_api_key_secret_arn  = var.runpod_api_key_secret_arn
  runpod_api_key_secret_name = var.runpod_api_key_secret_name
  artifacts_bucket_name      = var.artifacts_bucket_name
  artifacts_bucket_arn       = var.artifacts_bucket_arn
  api_invoke_url             = var.api_invoke_url
  timeout_seconds            = 300
}

module "invoke_lip_sync" {
  source = "../invoke_worker"

  project      = var.project
  env          = var.env
  stage_name   = "lip_sync"
  services_dir = var.services_dir

  runpod_endpoint_id         = var.runpod_lip_sync_endpoint_id
  runpod_api_key_secret_arn  = var.runpod_api_key_secret_arn
  runpod_api_key_secret_name = var.runpod_api_key_secret_name
  artifacts_bucket_name      = var.artifacts_bucket_name
  artifacts_bucket_arn       = var.artifacts_bucket_arn
  api_invoke_url             = var.api_invoke_url
  timeout_seconds            = 300
}

# ---------- update_job_failed ----------
# (there's no "update_job_complete" Lambda — the Fargate assembly container
# is the true final stage and marks the job COMPLETE itself via its task IAM
# role; see workers/assembly/main.py. UpdateJobFailed still exists as the
# Catch target for infra-level failures anywhere in the pipeline.)
data "archive_file" "update_job_failed" {
  type        = "zip"
  output_path = "${path.module}/build/update_job_failed.zip"

  source {
    content  = file("${var.services_dir}/update_job_failed/handler.py")
    filename = "handler.py"
  }
  source {
    content  = file("${var.services_dir}/common/dynamo.py")
    filename = "common/dynamo.py"
  }
  source {
    content  = file("${var.services_dir}/common/models.py")
    filename = "common/models.py"
  }
  source {
    content  = ""
    filename = "common/__init__.py"
  }
}

resource "aws_iam_role" "update_job_failed" {
  name               = "${var.project}-${var.env}-update-job-failed"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "update_job_failed_logs" {
  role       = aws_iam_role.update_job_failed.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "update_job_failed_perms" {
  name = "perms"
  role = aws_iam_role.update_job_failed.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.jobs_table_arn
      }
    ]
  })
}

resource "aws_lambda_function" "update_job_failed" {
  function_name    = "${var.project}-${var.env}-update-job-failed"
  role             = aws_iam_role.update_job_failed.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.update_job_failed.output_path
  source_code_hash = data.archive_file.update_job_failed.output_base64sha256

  environment {
    variables = {
      JOBS_TABLE = var.jobs_table_name
    }
  }
}
