# /generate and /jobs/{id} require a Cognito ID token (Bearer). The
# runpod-callback route stays unauthenticated at the API Gateway level — it's
# guarded by its own shared-secret header check inside the Lambda instead,
# since the caller there is RunPod, not an end user with a Cognito session.

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = var.api_id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project}-${var.env}-cognito"

  jwt_configuration {
    audience = [var.cognito_app_client_id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

resource "aws_apigatewayv2_integration" "submit_job" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.submit_job.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "submit_job" {
  api_id             = var.api_id
  route_key          = "POST /generate"
  target             = "integrations/${aws_apigatewayv2_integration.submit_job.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_integration" "get_job" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_job.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_job" {
  api_id             = var.api_id
  route_key          = "GET /jobs/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.get_job.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_integration" "runpod_callback" {
  api_id                 = var.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.runpod_callback.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "runpod_callback" {
  api_id    = var.api_id
  route_key = "POST /internal/runpod-callback/{stage}"
  target    = "integrations/${aws_apigatewayv2_integration.runpod_callback.id}"
}
