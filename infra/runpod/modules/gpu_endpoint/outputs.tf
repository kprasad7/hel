output "endpoint_id" {
  value = runpod_endpoint.this.id
}

output "endpoint_name" {
  value = runpod_endpoint.this.name
}

output "endpoint_run_url" {
  value = "https://api.runpod.ai/v2/${runpod_endpoint.this.id}/run"
}
