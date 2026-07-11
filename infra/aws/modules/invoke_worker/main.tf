# Reusable shape for a Step Functions "waitForTaskToken" invoker Lambda: one
# per pipeline stage (services/invoke_<stage_name>/handler.py), each with the
# same IAM shape (read the RunPod API key secret, presign an S3 upload URL)
# and the same env var contract. Stage-specific request-building logic lives
# in each handler.py; only the Terraform plumbing is shared here.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "archive_file" "this" {
  type        = "zip"
  output_path = "${path.module}/build/invoke_${var.stage_name}.zip"

  source {
    content  = file("${var.services_dir}/invoke_${var.stage_name}/handler.py")
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

resource "aws_iam_role" "this" {
  name               = "${var.project}-${var.env}-invoke-${replace(var.stage_name, "_", "-")}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "perms" {
  name = "perms"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.runpod_api_key_secret_arn
      },
      {
        # GetObject is only actually needed by invoke_lip_sync (reads the
        # video_gen/tts artifacts) but is harmless to grant uniformly here —
        # scoped to this one bucket, and simpler than a per-stage conditional.
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.artifacts_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.project}-${var.env}-invoke-${replace(var.stage_name, "_", "-")}"
  role             = aws_iam_role.this.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = var.timeout_seconds
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  environment {
    variables = {
      RUNPOD_ENDPOINT_ID         = var.runpod_endpoint_id
      RUNPOD_API_KEY_SECRET_NAME = var.runpod_api_key_secret_name
      ARTIFACTS_BUCKET           = var.artifacts_bucket_name
      API_INVOKE_URL             = var.api_invoke_url
    }
  }
}
