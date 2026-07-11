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

variable "jobs_table_name" {
  type = string
}

variable "jobs_table_arn" {
  type = string
}

variable "artifacts_bucket_name" {
  type = string
}

variable "artifacts_bucket_arn" {
  type = string
}

variable "runpod_api_key_secret_arn" {
  type = string
}

variable "runpod_api_key_secret_name" {
  type = string
}

variable "runpod_video_gen_endpoint_id" {
  type = string
}

variable "runpod_tts_endpoint_id" {
  type = string
}

variable "runpod_bg_audio_endpoint_id" {
  type = string
}

variable "runpod_lip_sync_endpoint_id" {
  type = string
}

variable "api_invoke_url" {
  type = string
}

variable "assembly_ecs_cluster_arn" {
  type = string
}

variable "assembly_task_definition_arn" {
  type = string
}

variable "assembly_subnet_ids" {
  type = list(string)
}

variable "assembly_security_group_id" {
  type = string
}

variable "assembly_task_role_arns" {
  type        = list(string)
  description = "Execution + task role ARNs for the assembly task definition — the state machine role needs iam:PassRole on both to launch it."
}
