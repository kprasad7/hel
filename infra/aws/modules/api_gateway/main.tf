# The HTTP API "shell" only. Routes/integrations are attached by the
# orchestration module (runpod-callback route) and the api module
# (submit-job / get-job routes) so that invoker Lambdas can know the
# API's invoke URL (needed to build RunPod callback_url values) without
# creating a dependency cycle between orchestration and api.
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project}-${var.env}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttle_burst_limit
    throttling_rate_limit  = var.throttle_rate_limit
  }
}
