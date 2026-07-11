# Verified against the runpod/runpod provider source
# (github.com/runpod/terraform-provider-runpod, internal/provider/resource_template
# and resource_endpoint gen schemas + examples/) on 2026-07-11. Confirm again if
# this is applied much later — a "community" tier provider can still move.

terraform {
  required_providers {
    runpod = {
      source  = "runpod/runpod"
      version = "~> 1.0"
    }
  }
}

resource "runpod_template" "this" {
  name                 = "${var.name}-template"
  image_name           = var.image
  container_disk_in_gb = var.container_disk_gb
  is_serverless        = true
  env                  = var.env
}

resource "runpod_endpoint" "this" {
  name         = var.name
  template_id  = runpod_template.this.id
  gpu_type_ids = var.gpu_type_ids
  gpu_count    = var.gpu_count
  workers_min  = var.workers_min # 0 = scale-to-zero, per the cost-optimized choice
  workers_max  = var.workers_max
  idle_timeout = var.idle_timeout_seconds
  scaler_type  = "QUEUE_DELAY"
  scaler_value = 4
}
