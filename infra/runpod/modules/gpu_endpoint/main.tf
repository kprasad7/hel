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

  # Explicitly set to avoid a real provider bug: when left unset (null), the
  # API returns concrete defaults for these, and the provider doesn't
  # implement "use state for unknown" correctly — Terraform then reports
  # "provider produced inconsistent result after apply" and the whole apply
  # fails. readme/container_registry_auth_id: the API returns "" regardless
  # of input, so we match that. ports: the RunPod API *always* returns
  # ["8888/http", "22/tcp"] for a template no matter what's sent — even an
  # empty list gets silently overridden server-side — so matching that
  # exactly (not the empty list you'd actually want for a serverless worker)
  # is the only way to stop the mismatch. These ports aren't used by
  # serverless workers anyway; harmless. Confirmed by hand against two real
  # applies on 2026-07-11.
  ports                      = ["8888/http", "22/tcp"]
  readme                     = ""
  container_registry_auth_id = ""

  lifecycle {
    # The `env` map still hits the same provider bug ("inconsistent values
    # for sensitive attribute") even when fully specified — apparently a
    # deeper issue in how this provider round-trips sensitive map values.
    # We already know what we set it to; not worth failing every apply over.
    ignore_changes = [env]
  }
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

  # Same "provider produced inconsistent result after apply" bug as the
  # template resource above, same fix: explicitly set every Optional field
  # we'd otherwise leave null, matching whatever concrete default the API
  # actually returns, so there's no null-vs-value mismatch for Terraform to
  # choke on. Confirmed by hand on 2026-07-11.
  network_volume_id     = ""
  network_volume_ids    = []
  env                   = {}
  allowed_cuda_versions = []
  cpu_flavor_ids        = []
  data_center_ids       = []
  min_cuda_version      = ""
  # cpu_flavor_priority / gpu_type_priority: the provider's schema declares
  # these, but the live RunPod REST API rejects them outright ("Extra input
  # keys provided in request body") — a real provider/API version mismatch.
  # Confirmed by hand on 2026-07-11; don't set them.
}
