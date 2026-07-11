# Deploying the full pipeline

Two independent Terraform stacks: `infra/aws` (all AWS resources, including
the Fargate assembly task) and `infra/runpod` (the four RunPod serverless
GPU endpoints). They're separate so each can be applied/destroyed
independently, but `infra/aws` needs the RunPod endpoint IDs and vice versa
— the AWS API's invoke URL needs to reach the RunPod workers as a callback
target — so apply happens in a specific order below. Both are validated
(`terraform validate` + a real `terraform plan` against the actual AWS
account) as of this writing; **neither has been `terraform apply`'d** —
that creates real, billable resources and needs an explicit go-ahead plus a
RunPod API key.

## 0. Prerequisites

- AWS account + credentials configured (`aws configure` or env vars) with
  permission to create the resources in `infra/aws`.
- A RunPod account + API key (console.runpod.io → Settings → API Keys).
- Docker, to build the worker images, and a container registry the RunPod
  provider can pull from (GHCR/Docker Hub — public repo is simplest to
  start; private requires RunPod registry auth, see
  `runpod_container_registry_auth` if needed later).
- `pip` and `bash` on the machine running `terraform apply` for `infra/aws`
  — the `runpod_callback` Lambda vendors a real dependency (`cramjam`) via a
  `local-exec` build step (see step 6b). Git Bash on Windows is fine.

## 1. Bootstrap Terraform remote state (once, by hand)

Both stacks' `backend "s3"` blocks are intentionally left blank in this repo.
Create the bucket + lock table once, then fill in each stack's backend block
(or pass `-backend-config` flags) before the first `terraform init`:

```
aws s3api create-bucket --bucket <project>-tf-state --region <region>
aws s3api put-bucket-versioning --bucket <project>-tf-state --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name <project>-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

## 2. Build and push the RunPod worker images

From the repo root (`video-platform/`), so `workers/common` is in the build
context, for each of `video_gen`, `tts`, `bg_audio`, `lip_sync`:

```
docker build -f workers/video_gen/Dockerfile -t ghcr.io/<org>/video-gen:latest .
docker push ghcr.io/<org>/video-gen:latest

docker build -f workers/tts/Dockerfile -t ghcr.io/<org>/tts:latest .
docker push ghcr.io/<org>/tts:latest

docker build -f workers/bg_audio/Dockerfile -t ghcr.io/<org>/bg-audio:latest .
docker push ghcr.io/<org>/bg-audio:latest

docker build -f workers/lip_sync/Dockerfile -t ghcr.io/<org>/lip-sync:latest .
docker push ghcr.io/<org>/lip-sync:latest
```

`lip_sync` bakes in several GB of MuseTalk model weights (`download_weights.sh`
runs at build time) — expect a slow first build and a large pushed image.

## 3. Apply infra/aws once, without the RunPod endpoint IDs, to get the API URL

The `orchestration` module needs the API Gateway invoke URL (to build RunPod
callback URLs) and the RunPod endpoint IDs (to call the right endpoints) —
apply AWS first with placeholder endpoint IDs, note the API URL, then apply
RunPod, then re-apply AWS with the real endpoint IDs. This first apply also
creates the `assembly` ECR repository (needed for step 3b):

```
cd infra/aws/envs/beta
terraform init
terraform apply \
  -var="runpod_video_gen_endpoint_id=placeholder" \
  -var="runpod_tts_endpoint_id=placeholder" \
  -var="runpod_bg_audio_endpoint_id=placeholder" \
  -var="runpod_lip_sync_endpoint_id=placeholder"
terraform output api_invoke_url               # note this value
terraform output assembly_ecr_repository_url   # note this value, for step 3b
```

## 3b. Build and push the assembly image

Unlike the RunPod workers, the assembly image's ECR repo is created BY this
Terraform stack (step 3), so build/push it there specifically:

```
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <ecr_repository_url without the tag>
docker build -f workers/assembly/Dockerfile -t <assembly_ecr_repository_url>:latest .
docker push <assembly_ecr_repository_url>:latest
```

The ECS task definition was already registered in step 3 pointing at this
`:latest` tag — no re-apply needed, ECS just needs the image to exist by the
time a task actually runs.

## 4. Populate secrets

The `secrets` module creates Secrets Manager entries with placeholder values
(`REPLACE_ME`) so real credentials never touch Terraform state/version
control. Fill them in:

```
aws secretsmanager put-secret-value --secret-id vidplatform-beta-runpod-api-key \
  --secret-string "<your RunPod API key>"
aws secretsmanager put-secret-value --secret-id vidplatform-beta-callback-shared-secret \
  --secret-string "<a random shared secret you generate>"
```

Generate the shared secret however you like, e.g. `openssl rand -hex 32`. The
same value goes into `infra/runpod`'s `callback_shared_secret` variable below
— it's how `runpod_callback` verifies a webhook actually came from our
workers.

## 5. Apply infra/runpod

```
cd infra/runpod/envs/beta
terraform init
terraform apply \
  -var="runpod_api_key=<your RunPod API key>" \
  -var="callback_shared_secret=<same value as step 4>" \
  -var="video_gen_image=ghcr.io/<org>/video-gen:latest" \
  -var="tts_image=ghcr.io/<org>/tts:latest" \
  -var="bg_audio_image=ghcr.io/<org>/bg-audio:latest" \
  -var="lip_sync_image=ghcr.io/<org>/lip-sync:latest"
terraform output   # note video_gen_endpoint_id, tts_endpoint_id, bg_audio_endpoint_id, lip_sync_endpoint_id
```

## 6. Re-apply infra/aws with the real RunPod endpoint IDs

```
cd infra/aws/envs/beta
terraform apply \
  -var="runpod_video_gen_endpoint_id=<value from step 5>" \
  -var="runpod_tts_endpoint_id=<value from step 5>" \
  -var="runpod_bg_audio_endpoint_id=<value from step 5>" \
  -var="runpod_lip_sync_endpoint_id=<value from step 5>"
```

## 6b. (Optional) Wire up Grafana Cloud for GPU profiling metrics

Skip this if you just want the pipeline running — `runpod_callback` no-ops
the metrics push when `grafana_remote_write_url` is unset, which is a valid
"not configured yet" state. (Note: this only covers the four RunPod GPU
stages — the Fargate assembly stage's timings land in DynamoDB but aren't
pushed to Grafana yet, since it isn't a GPU stage and runs outside the
callback-Lambda path; a follow-up if that data's needed too.)

1. Create a free Grafana Cloud stack (grafana.com/auth/sign-up), find its
   Prometheus data source details (Connections → Data sources → your stack's
   Prometheus → note the remote_write URL and the Instance ID/username).
2. Generate an API token with `metrics:write` scope.
3. Populate the secret: `aws secretsmanager put-secret-value --secret-id vidplatform-beta-grafana-api-key --secret-string "<token>"`
4. Re-apply with the URL/user set (include all four `runpod_*_endpoint_id`
   vars from step 6 too):
   ```
   terraform apply \
     -var="runpod_video_gen_endpoint_id=<value from step 5>" \
     -var="runpod_tts_endpoint_id=<value from step 5>" \
     -var="runpod_bg_audio_endpoint_id=<value from step 5>" \
     -var="runpod_lip_sync_endpoint_id=<value from step 5>" \
     -var="grafana_remote_write_url=<https://.../api/prom/push>" \
     -var="grafana_remote_write_user=<instance id>"
   ```

## 8. Deploy the frontend

```
# fill in frontend/config.js with the four terraform outputs first:
#   api_invoke_url, aws_region, cognito_user_pool_id, cognito_app_client_id
aws s3 sync frontend/ s3://<ui_static_bucket_name>/ --exclude ".git/*"
aws cloudfront create-invalidation --distribution-id <cdn distribution_id output> --paths "/*"
```

Visit `https://<cdn_domain_name>` (terraform output), sign up, confirm via
the emailed code, sign in, and submit a prompt.

## 9. Smoke test (API directly, without the frontend)

`/generate` and `/jobs/{id}` require a Cognito ID token now (`Authorization: Bearer <token>`).
Easiest to get one is signing in through the frontend and copying
`sessionStorage.getItem("id_token")` from the browser devtools console, or
via the CLI:

```
aws cognito-idp sign-up --client-id <cognito_app_client_id> --username you@example.com --password "<password>"
aws cognito-idp admin-confirm-sign-up --user-pool-id <cognito_user_pool_id> --username you@example.com
aws cognito-idp initiate-auth --client-id <cognito_app_client_id> --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=you@example.com,PASSWORD=<password> \
  --query 'AuthenticationResult.IdToken' --output text
```

```
curl -X POST "<api_invoke_url>/generate" -H "Content-Type: application/json" \
  -H "Authorization: Bearer <id_token>" \
  -d '{"prompt": "a corgi surfing a small wave at sunset"}'
# -> {"job_id": "...", "status": "PENDING"}

curl "<api_invoke_url>/jobs/<job_id>" -H "Authorization: Bearer <id_token>"
# poll until status is COMPLETE or FAILED — output_url is the final,
# fully-assembled video (visuals + lip-synced narration + mixed bg music)
```

If it hangs: check the Step Functions execution in the AWS Console —
`ParallelGeneration`'s three branches run first, then `InvokeLipSync`, then
`AssembleFinalVideo` (an ECS/Fargate task, not a Lambda — check its logs
under the `/ecs/vidplatform-beta-assembly` CloudWatch log group, not a
Lambda log group). Also check the `invoke_*` and `runpod_callback` Lambda
logs, and each RunPod endpoint's request logs in console.runpod.io/serverless.
A single failed parallel branch fails the whole `ParallelGeneration` state
(and cancels the sibling branches) by design.

## Notes / known gaps at this stage

- TTS narration and the background-music prompt both currently reuse the
  same `prompt` field submitted for the video (no separate narration-script
  field in the API yet) — a deliberate v1 simplification, not an oversight.
- RunPod GPU type ID strings (`gpu_type_ids` in
  `infra/runpod/modules/gpu_endpoint`) should be double-checked against the
  `runpod_gpu_types` data source before relying on them — RunPod's catalog
  naming can change.
- The `lip_sync` worker shells out to MuseTalk's CLI script per request
  rather than keeping the model resident in memory — every invocation pays
  full model-load cost, unlike the other three RunPod stages. Flagged as a
  known optimization target in `workers/lip_sync/handler.py`, not fixed yet.
- The assembly Fargate task runs in the AWS account's **default VPC** with a
  public IP (no NAT Gateway) to avoid fixed monthly networking cost — fine
  for this pipeline (only needs to reach S3/DynamoDB/ECR, nothing calls into
  it), but revisit if this ever needs to run in a locked-down private subnet.
