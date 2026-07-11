data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- submit_job ----------
data "archive_file" "submit_job" {
  type        = "zip"
  output_path = "${path.module}/build/submit_job.zip"

  source {
    content  = file("${var.services_dir}/submit_job/handler.py")
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

resource "aws_iam_role" "submit_job" {
  name               = "${var.project}-${var.env}-submit-job"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "submit_job_logs" {
  role       = aws_iam_role.submit_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "submit_job_perms" {
  name = "perms"
  role = aws_iam_role.submit_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.jobs_table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = var.state_machine_arn
      }
    ]
  })
}

resource "aws_lambda_function" "submit_job" {
  function_name    = "${var.project}-${var.env}-submit-job"
  role             = aws_iam_role.submit_job.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.submit_job.output_path
  source_code_hash = data.archive_file.submit_job.output_base64sha256

  environment {
    variables = {
      JOBS_TABLE        = var.jobs_table_name
      STATE_MACHINE_ARN = var.state_machine_arn
    }
  }
}

resource "aws_lambda_permission" "submit_job_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.submit_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}

# ---------- get_job ----------
data "archive_file" "get_job" {
  type        = "zip"
  output_path = "${path.module}/build/get_job.zip"

  source {
    content  = file("${var.services_dir}/get_job/handler.py")
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

resource "aws_iam_role" "get_job" {
  name               = "${var.project}-${var.env}-get-job"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "get_job_logs" {
  role       = aws_iam_role.get_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "get_job_perms" {
  name = "perms"
  role = aws_iam_role.get_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.jobs_table_arn
      }
    ]
  })
}

resource "aws_lambda_function" "get_job" {
  function_name    = "${var.project}-${var.env}-get-job"
  role             = aws_iam_role.get_job.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.get_job.output_path
  source_code_hash = data.archive_file.get_job.output_base64sha256

  environment {
    variables = {
      JOBS_TABLE = var.jobs_table_name
    }
  }
}

resource "aws_lambda_permission" "get_job_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}

# ---------- runpod_callback ----------
# Unlike the other Lambdas here, this one has a real third-party dependency
# (cramjam, for Snappy compression of the Prometheus remote_write payload —
# see services/common/remote_write.py), so it can't just be zipped from raw
# .py files like the rest. A local-exec step vendors the dependency into a
# build dir (as manylinux wheels, matching the Lambda runtime) before zipping.
# Requires `pip` and `bash` on the machine running `terraform apply`.
locals {
  runpod_callback_src_dir = "${path.module}/build/runpod_callback_src"
}

resource "null_resource" "runpod_callback_deps" {
  triggers = {
    requirements_hash = filemd5("${var.services_dir}/runpod_callback/requirements.txt")
    handler_hash      = filemd5("${var.services_dir}/runpod_callback/handler.py")
    remote_write_hash = filemd5("${var.services_dir}/common/remote_write.py")
    dynamo_hash       = filemd5("${var.services_dir}/common/dynamo.py")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      rm -rf "${local.runpod_callback_src_dir}"
      mkdir -p "${local.runpod_callback_src_dir}/common"
      cp "${var.services_dir}/runpod_callback/handler.py" "${local.runpod_callback_src_dir}/handler.py"
      cp "${var.services_dir}/common/dynamo.py" "${local.runpod_callback_src_dir}/common/dynamo.py"
      cp "${var.services_dir}/common/models.py" "${local.runpod_callback_src_dir}/common/models.py"
      cp "${var.services_dir}/common/remote_write.py" "${local.runpod_callback_src_dir}/common/remote_write.py"
      : > "${local.runpod_callback_src_dir}/common/__init__.py"
      pip install --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 \
        --only-binary=:all: --target "${local.runpod_callback_src_dir}" \
        -r "${var.services_dir}/runpod_callback/requirements.txt"
    EOT
  }
}

data "archive_file" "runpod_callback" {
  type        = "zip"
  output_path = "${path.module}/build/runpod_callback.zip"
  source_dir  = local.runpod_callback_src_dir

  depends_on = [null_resource.runpod_callback_deps]
}

resource "aws_iam_role" "runpod_callback" {
  name               = "${var.project}-${var.env}-runpod-callback"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "runpod_callback_logs" {
  role       = aws_iam_role.runpod_callback.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "runpod_callback_perms" {
  name = "perms"
  role = aws_iam_role.runpod_callback.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.callback_shared_secret_arn, var.grafana_api_key_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.jobs_table_arn
      },
      {
        # Task token targets are dynamic per-execution, hence resource "*" —
        # this is the AWS-documented pattern for SendTaskSuccess/Failure.
        Effect   = "Allow"
        Action   = ["states:SendTaskSuccess", "states:SendTaskFailure"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "runpod_callback" {
  function_name    = "${var.project}-${var.env}-runpod-callback"
  role             = aws_iam_role.runpod_callback.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.runpod_callback.output_path
  source_code_hash = data.archive_file.runpod_callback.output_base64sha256

  environment {
    variables = {
      JOBS_TABLE                  = var.jobs_table_name
      CALLBACK_SECRET_NAME        = var.callback_shared_secret_name
      GRAFANA_REMOTE_WRITE_URL    = var.grafana_remote_write_url
      GRAFANA_REMOTE_WRITE_USER   = var.grafana_remote_write_user
      GRAFANA_API_KEY_SECRET_NAME = var.grafana_api_key_secret_name
    }
  }
}

resource "aws_lambda_permission" "runpod_callback_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.runpod_callback.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}
