variable "project" {
  type    = string
  default = "vidplatform"
}

variable "env" {
  type    = string
  default = "beta"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "runpod_video_gen_endpoint_id" {
  type        = string
  description = "Output of infra/runpod/envs/beta (video_gen_endpoint_id) — apply that stack first, copy the value here."
}

variable "runpod_tts_endpoint_id" {
  type        = string
  description = "Output of infra/runpod/envs/beta (tts_endpoint_id)."
}

variable "runpod_bg_audio_endpoint_id" {
  type        = string
  description = "Output of infra/runpod/envs/beta (bg_audio_endpoint_id)."
}

variable "runpod_lip_sync_endpoint_id" {
  type        = string
  description = "Output of infra/runpod/envs/beta (lip_sync_endpoint_id)."
}

variable "grafana_remote_write_url" {
  type        = string
  default     = ""
  description = "Grafana Cloud Prometheus remote_write endpoint (e.g. https://<host>/api/prom/push). Leave empty to skip GPU metrics push entirely."
}

variable "grafana_remote_write_user" {
  type        = string
  default     = ""
  description = "Grafana Cloud stack's Prometheus instance ID (Basic Auth username for remote_write)."
}

variable "assembly_image" {
  type        = string
  default     = "ghcr.io/kprasad7/hel-assembly:latest"
  description = "Full image reference for the Fargate assembly task, pulled directly from GHCR (no ECR involved)."
}
