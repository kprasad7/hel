locals {
  services_dir = abspath("${path.module}/../../../../services")
}

module "storage" {
  source = "../../modules/storage"

  project = var.project
  env     = var.env
}

module "database" {
  source = "../../modules/database"

  project = var.project
  env     = var.env
}

module "secrets" {
  source = "../../modules/secrets"

  project = var.project
  env     = var.env
}

module "api_gateway" {
  source = "../../modules/api_gateway"

  project = var.project
  env     = var.env
}

module "auth" {
  source = "../../modules/auth"

  project = var.project
  env     = var.env
}

module "cdn" {
  source = "../../modules/cdn"

  project = var.project
  env     = var.env

  ui_static_bucket_name                 = module.storage.ui_static_bucket_name
  ui_static_bucket_arn                  = module.storage.ui_static_bucket_arn
  ui_static_bucket_regional_domain_name = module.storage.ui_static_bucket_regional_domain_name
}

module "assembly" {
  source = "../../modules/assembly"

  project = var.project
  env     = var.env

  artifacts_bucket_name   = module.storage.artifacts_bucket_name
  artifacts_bucket_arn    = module.storage.artifacts_bucket_arn
  artifacts_bucket_domain = module.storage.artifacts_bucket_domain

  jobs_table_name = module.database.jobs_table_name
  jobs_table_arn  = module.database.jobs_table_arn
}

# Depends on api_gateway (for the callback URL) and secrets/database/storage,
# but NOT on the api module — this ordering avoids a dependency cycle since
# submit_job (in the api module) needs this module's state_machine_arn.
module "orchestration" {
  source = "../../modules/orchestration"

  project      = var.project
  env          = var.env
  services_dir = local.services_dir

  jobs_table_name = module.database.jobs_table_name
  jobs_table_arn  = module.database.jobs_table_arn

  artifacts_bucket_name = module.storage.artifacts_bucket_name
  artifacts_bucket_arn  = module.storage.artifacts_bucket_arn

  runpod_api_key_secret_arn    = module.secrets.runpod_api_key_secret_arn
  runpod_api_key_secret_name   = module.secrets.runpod_api_key_secret_name
  runpod_video_gen_endpoint_id = var.runpod_video_gen_endpoint_id
  runpod_tts_endpoint_id       = var.runpod_tts_endpoint_id
  runpod_bg_audio_endpoint_id  = var.runpod_bg_audio_endpoint_id
  runpod_lip_sync_endpoint_id  = var.runpod_lip_sync_endpoint_id

  api_invoke_url = module.api_gateway.invoke_url

  assembly_ecs_cluster_arn     = module.assembly.ecs_cluster_arn
  assembly_task_definition_arn = module.assembly.task_definition_arn
  assembly_subnet_ids          = module.assembly.subnet_ids
  assembly_security_group_id   = module.assembly.security_group_id
  assembly_task_role_arns      = [module.assembly.execution_role_arn, module.assembly.task_role_arn]
}

module "api" {
  source = "../../modules/api"

  project      = var.project
  env          = var.env
  services_dir = local.services_dir

  api_id            = module.api_gateway.api_id
  api_execution_arn = module.api_gateway.execution_arn

  jobs_table_name = module.database.jobs_table_name
  jobs_table_arn  = module.database.jobs_table_arn

  state_machine_arn = module.orchestration.state_machine_arn

  callback_shared_secret_arn  = module.secrets.callback_shared_secret_arn
  callback_shared_secret_name = module.secrets.callback_shared_secret_name

  grafana_api_key_secret_arn  = module.secrets.grafana_api_key_secret_arn
  grafana_api_key_secret_name = module.secrets.grafana_api_key_secret_name
  grafana_remote_write_url    = var.grafana_remote_write_url
  grafana_remote_write_user   = var.grafana_remote_write_user

  cognito_user_pool_id  = module.auth.user_pool_id
  cognito_app_client_id = module.auth.app_client_id
  aws_region            = var.aws_region
}
