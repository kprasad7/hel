variable "project" {
  type    = string
  default = "vidplatform"
}

variable "env" {
  type    = string
  default = "beta"
}

variable "runpod_api_key" {
  type      = string
  sensitive = true
}

variable "callback_shared_secret" {
  type        = string
  sensitive   = true
  description = "Must match the value stored in AWS Secrets Manager (infra/aws secrets module) for the runpod-callback Lambda to accept these workers' callbacks."
}

variable "video_gen_image" {
  type        = string
  description = "e.g. ghcr.io/org/video-gen:sha-abc123 — pushed by CI before apply."
}

variable "video_gen_workers_max" {
  type    = number
  default = 3
}

variable "tts_image" {
  type        = string
  description = "e.g. ghcr.io/org/tts:sha-abc123 — pushed by CI before apply."
}

variable "tts_workers_max" {
  type    = number
  default = 3
}

variable "bg_audio_image" {
  type        = string
  description = "e.g. ghcr.io/org/bg-audio:sha-abc123 — pushed by CI before apply."
}

variable "bg_audio_workers_max" {
  type    = number
  default = 3
}

variable "lip_sync_image" {
  type        = string
  description = "e.g. ghcr.io/org/lip-sync:sha-abc123 — pushed by CI before apply."
}

variable "lip_sync_workers_max" {
  type    = number
  default = 3
}
