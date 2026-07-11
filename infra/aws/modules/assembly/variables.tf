variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag within this module's own ECR repo. The repo is created by this module; push the built image there before the task is actually run (task definition registration doesn't require the image to exist yet, only RunTask does)."
}

variable "artifacts_bucket_name" {
  type = string
}

variable "artifacts_bucket_arn" {
  type = string
}

variable "artifacts_bucket_domain" {
  type = string
}

variable "jobs_table_name" {
  type = string
}

variable "jobs_table_arn" {
  type = string
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memory" {
  type    = number
  default = 2048
}
