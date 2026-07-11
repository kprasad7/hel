# RunPod API key and the callback shared secret are created here with placeholder
# values and populated out-of-band (console, or `aws secretsmanager put-secret-value`)
# so real credentials never enter Terraform state or version control.

resource "aws_secretsmanager_secret" "runpod_api_key" {
  name = "${var.project}-${var.env}-runpod-api-key"
}

resource "aws_secretsmanager_secret_version" "runpod_api_key" {
  secret_id     = aws_secretsmanager_secret.runpod_api_key.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "callback_shared_secret" {
  name = "${var.project}-${var.env}-callback-shared-secret"
}

resource "aws_secretsmanager_secret_version" "callback_shared_secret" {
  secret_id     = aws_secretsmanager_secret.callback_shared_secret.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Optional: only populated if/when Grafana Cloud remote_write is set up.
# runpod_callback checks GRAFANA_REMOTE_WRITE_URL and no-ops the metrics push
# if it's unset, so leaving this as REPLACE_ME is a valid "not configured yet"
# state, not a broken one.
resource "aws_secretsmanager_secret" "grafana_api_key" {
  name = "${var.project}-${var.env}-grafana-api-key"
}

resource "aws_secretsmanager_secret_version" "grafana_api_key" {
  secret_id     = aws_secretsmanager_secret.grafana_api_key.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
