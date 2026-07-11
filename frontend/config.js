// Filled in after `terraform apply` (infra/aws/envs/beta) — see infra/README.md.
// Not a secret: the Cognito app client has no client secret (public SPA client),
// and the API URL/pool IDs are meant to be visible to the browser.
window.APP_CONFIG = {
  API_INVOKE_URL: "REPLACE_ME", // terraform output api_invoke_url
  AWS_REGION: "us-east-1", // must match infra/aws/envs/beta's aws_region
  COGNITO_USER_POOL_ID: "REPLACE_ME", // terraform output cognito_user_pool_id
  COGNITO_APP_CLIENT_ID: "REPLACE_ME", // terraform output cognito_app_client_id
};
