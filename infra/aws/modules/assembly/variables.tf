variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "image" {
  type        = string
  description = "Full image reference the Fargate task pulls, e.g. ghcr.io/org/hel-assembly:latest. Built/pushed by .github/workflows/build-images.yml alongside the RunPod worker images — no ECR needed, ECS can pull public GHCR images directly."
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
