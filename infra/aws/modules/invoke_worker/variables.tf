variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "stage_name" {
  type        = string
  description = "Matches services/invoke_<stage_name>/handler.py, e.g. \"video_gen\", \"tts\", \"bg_audio\"."
}

variable "services_dir" {
  type = string
}

variable "runpod_endpoint_id" {
  type = string
}

variable "runpod_api_key_secret_arn" {
  type = string
}

variable "runpod_api_key_secret_name" {
  type = string
}

variable "artifacts_bucket_name" {
  type = string
}

variable "artifacts_bucket_arn" {
  type = string
}

variable "api_invoke_url" {
  type = string
}

variable "timeout_seconds" {
  type    = number
  default = 20
}
