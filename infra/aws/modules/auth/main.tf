resource "aws_cognito_user_pool" "this" {
  name = "${var.project}-${var.env}-users"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

# Public client (no secret) — the frontend is a static SPA and can't keep a
# client secret confidential, so it authenticates users directly via
# USER_PASSWORD_AUTH/SRP and sends the resulting ID token as a Bearer token.
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.project}-${var.env}-spa"
  user_pool_id = aws_cognito_user_pool.this.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  generate_secret = false

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
