output "runpod_api_key_secret_arn" {
  value = aws_secretsmanager_secret.runpod_api_key.arn
}

output "runpod_api_key_secret_name" {
  value = aws_secretsmanager_secret.runpod_api_key.name
}

output "callback_shared_secret_arn" {
  value = aws_secretsmanager_secret.callback_shared_secret.arn
}

output "callback_shared_secret_name" {
  value = aws_secretsmanager_secret.callback_shared_secret.name
}

output "grafana_api_key_secret_arn" {
  value = aws_secretsmanager_secret.grafana_api_key.arn
}

output "grafana_api_key_secret_name" {
  value = aws_secretsmanager_secret.grafana_api_key.name
}
