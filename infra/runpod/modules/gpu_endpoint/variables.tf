variable "name" {
  type = string
}

variable "image" {
  type        = string
  description = "Full image ref, e.g. ghcr.io/org/video-gen:sha-abc123"
}

variable "container_disk_gb" {
  type    = number
  default = 20
}

variable "gpu_type_ids" {
  type        = list(string)
  default     = ["NVIDIA A100 80GB PCIe"]
  description = "GPU type ID strings as returned by the runpod_gpu_types data source's `id` field (RunPod uses human-readable IDs like this one, not opaque UUIDs) — re-verify with that data source if endpoint creation fails on this field."
}

variable "gpu_count" {
  type        = number
  default     = 1
  description = "GPUs per worker."
}

variable "workers_min" {
  type    = number
  default = 0
}

variable "workers_max" {
  type    = number
  default = 3
}

variable "idle_timeout_seconds" {
  type    = number
  default = 5
}

variable "env" {
  type    = map(string)
  default = {}
}
