output "api_invoke_url" {
  value = module.api_gateway.invoke_url
}

output "jobs_table_name" {
  value = module.database.jobs_table_name
}

output "artifacts_bucket_name" {
  value = module.storage.artifacts_bucket_name
}

output "state_machine_arn" {
  value = module.orchestration.state_machine_arn
}

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_app_client_id" {
  value = module.auth.app_client_id
}

output "cdn_domain_name" {
  value = module.cdn.domain_name
}

output "ui_static_bucket_name" {
  value = module.storage.ui_static_bucket_name
}
