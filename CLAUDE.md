# Video Generation Platform

An open-source, fal.ai-style platform: a user submits a text prompt and gets back a finished short
video — generated visuals, narrated speech, lip-synced mouth movement, and mixed background
music/SFX. GPU inference runs on RunPod Serverless (A100, scale-to-zero); all other infrastructure
is serverless AWS, provisioned entirely with Terraform.

Full architecture and rationale: see the plan this was built from —
`C:\Users\sree\.claude\plans\hey-i-want-build-happy-taco.md` (kept as the historical design doc;
this file is the living summary, update it as the system evolves).

## Pipeline

```
prompt → [video_gen | tts | bg_audio] (parallel) → lip_sync → assembly (ffmpeg, Fargate) → final video
```

| Stage | Model | Runtime |
|---|---|---|
| Text-to-video | LTX-Video | RunPod serverless, A100 |
| TTS narration | Kokoro-82M | RunPod serverless, A100 |
| Background music/SFX | Stable Audio Open | RunPod serverless, A100 |
| Lip-sync | MuseTalk | RunPod serverless, A100 |
| Assembly (mux/mix) | ffmpeg | AWS Fargate task (CPU only) |

Orchestration is an AWS Step Functions state machine (`ParallelGeneration` → `InvokeLipSync` →
`AssembleFinalVideo`). Each RunPod stage is invoked with the `waitForTaskToken` pattern: a Lambda
submits the job to RunPod with a callback URL carrying the task token; RunPod's webhook on
completion resumes the state machine via `SendTaskSuccess`/`SendTaskFailure`. The final assembly
stage is different: it's a Fargate task invoked via Step Functions' native `ecs:runTask.sync`
integration (no callback/token plumbing needed — Step Functions blocks natively until the ECS task
exits), and because it runs fully inside AWS it has a scoped IAM task role and writes directly to
S3/DynamoDB, marking the job COMPLETE/FAILED itself rather than going through a dedicated Lambda.

Every RunPod worker returns a structured GPU profiling payload with its result (cold-start time,
per-stage timing, GPU utilization/memory/power samples) — persisted to DynamoDB, and (optionally)
pushed to Grafana Cloud via Prometheus `remote_write` for dashboarding. RunPod Serverless workers
are ephemeral/scale-to-zero, so metrics are push-based, not scraped — see
`services/common/remote_write.py` and `infra/README.md` step 6b. Superseded the plan doc's original
CloudWatch-EMF idea after digging into RunPod's own monitoring landscape mid-build. The assembly
stage's timings land in DynamoDB too but aren't pushed to Grafana yet (it's not a GPU stage and
doesn't go through the callback Lambda) — a known gap, not an oversight.

## Repo layout

```
workers/            # one dir per pipeline-stage Docker image + inference/handler code
  common/            # shared RunPod-worker code (GpuProfiler/StageTimer, callback POST, S3 upload)
  video_gen/         # RunPod: LTX-Video
  tts/               # RunPod: Kokoro-82M
  bg_audio/          # RunPod: Stable Audio Open
  lip_sync/          # RunPod: MuseTalk (vendors the upstream repo; see handler.py docstring for
                      #   why this stage doesn't get warm-start benefit like the others)
  assembly/          # Fargate (not RunPod): ffmpeg mix/mux, plain boto3 + subprocess
services/            # AWS Lambda function source
  submit_job/
  get_job/
  runpod_callback/   # also pushes GPU profiling metrics to Grafana Cloud, if configured
  invoke_video_gen/  # Step Functions task Lambdas — submit to RunPod, don't wait
  invoke_tts/
  invoke_bg_audio/
  invoke_lip_sync/   # unlike the others, reads two prior artifacts (video + narration), not just prompt
  update_job_failed/ # (no update_job_complete — see Pipeline section above)
  common/            # shared Lambda code (DynamoDB access, models, remote_write encoder)
infra/
  aws/               # Terraform for AWS (S3, DynamoDB, API Gateway, Step Functions, Fargate, ...)
    modules/invoke_worker/  # reusable module behind invoke_video_gen/tts/bg_audio/lip_sync
    modules/assembly/       # ECR + ECS cluster + Fargate task def for the assembly stage
    modules/auth/           # Cognito User Pool + public SPA app client
    modules/cdn/            # CloudFront + OAC in front of the ui-static S3 bucket
  runpod/            # Terraform for RunPod serverless endpoints (runpod/runpod provider)
  README.md          # deploy order + bootstrap steps for both stacks
frontend/            # static UI, no build step (index.html + app.js + style.css + config.js)
  config.js          # runtime config (API URL, Cognito IDs) — filled in after terraform apply
```

## Status

Build is following the phased order in the plan doc: walking skeleton (video_gen stage only)
first, then TTS + bg_audio in parallel, then lip_sync, then assembly, then auth/observability/UI.
Update this section as stages land.

- [x] Full pipeline wired end-to-end: video_gen + tts + bg_audio (parallel) → lip_sync → Fargate
      assembly.
- [x] Grafana Cloud `remote_write` push for GPU profiling metrics (optional — no-ops if
      unconfigured; covers the 4 RunPod stages, not yet the Fargate assembly stage)
- [x] Cognito auth (JWT authorizer on `/generate` and `/jobs/{id}`; `/internal/runpod-callback/{stage}`
      stays open at the gateway level, guarded by its own shared-secret header check instead) +
      API Gateway throttling (stage-level `default_route_settings`, already part of `api_gateway` module)
- [x] Frontend UI: vanilla HTML/CSS/JS (no build step), Cognito sign-up/confirm/sign-in, prompt
      submit, status polling, video playback. Served via CloudFront + a private (OAC-only) S3 bucket.

`terraform validate` and a real `terraform plan` (against the actual AWS account, and the real
RunPod provider registry) both pass clean for the full stack — **not yet `terraform apply`'d**
(costs money / creates real resources; needs an explicit go-ahead plus a RunPod API key and
built/pushed worker + assembly images, see `infra/README.md`). That real deploy + end-to-end smoke
test is the natural next step once the user is ready to spend.

## Conventions

- Every RunPod worker is a self-contained Docker image (one model per image) — swapping a model
  means changing one image, not the pipeline. The assembly stage is the one exception: it's a
  Fargate task, not a RunPod endpoint, because it's CPU-only work with no GPU need.
- RunPod workers never hold AWS credentials (they're external to AWS) — artifact I/O uses presigned
  S3 URLs passed into the job payload by the submitting Lambda. The Fargate assembly task is
  different: it runs inside AWS, so it gets a scoped IAM task role and calls S3/DynamoDB directly.
- DynamoDB single-table design: `JOB#<id>` / `META` for job status, `JOB#<id>` / `PROFILE#<stage>`
  for per-stage profiling records.
- Terraform state lives in a dedicated `tf-state` S3 bucket + DynamoDB lock table (bootstrapped
  once, outside the normal apply).
- TTS narration and the background-music generation prompt both currently reuse the same `prompt`
  submitted for the video — no separate narration-script field in the API yet (deliberate v1
  simplification, see `infra/README.md` known gaps).
