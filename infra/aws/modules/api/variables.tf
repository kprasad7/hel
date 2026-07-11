variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "services_dir" {
  type        = string
  description = "Absolute path to the repo's services/ directory (Lambda source)."
}

variable "api_id" {
  type = string
}

variable "api_execution_arn" {
  type = string
}

variable "jobs_table_name" {
  type = string
}

variable "jobs_table_arn" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "callback_shared_secret_arn" {
  type = string
}

variable "callback_shared_secret_name" {
  type = string
}

variable "grafana_api_key_secret_arn" {
  type = string
}

variable "grafana_api_key_secret_name" {
  type = string
}

variable "grafana_remote_write_url" {
  type        = string
  default     = ""
  description = "Grafana Cloud Prometheus remote_write endpoint. Empty = metrics push disabled."
}

variable "grafana_remote_write_user" {
  type        = string
  default     = ""
  description = "Grafana Cloud stack's Prometheus instance ID (used as Basic Auth username)."
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_app_client_id" {
  type = string
}

variable "aws_region" {
  type        = string
  description = "Needed to build the Cognito JWT issuer URL for the API Gateway authorizer."
}
