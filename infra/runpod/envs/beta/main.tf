terraform {
  required_version = ">= 1.5"

  required_providers {
    runpod = {
      source  = "runpod/runpod"
      version = "~> 1.0"
    }
  }

  backend "s3" {
    # Fill in after the AWS tf-state bucket/lock table exist (bootstrap module, or
    # create by hand once): bucket, key = "runpod/beta/terraform.tfstate", region,
    # dynamodb_table for locking.
  }
}

provider "runpod" {
  api_key = var.runpod_api_key
}

module "video_gen" {
  source = "../../modules/gpu_endpoint"

  name              = "${var.project}-${var.env}-video-gen"
  image             = var.video_gen_image
  workers_min       = 0 # scale-to-zero
  workers_max       = var.video_gen_workers_max
  container_disk_gb = 30

  env = {
    MODEL_ID               = "Lightricks/LTX-Video"
    CALLBACK_SHARED_SECRET = var.callback_shared_secret
  }
}

module "tts" {
  source = "../../modules/gpu_endpoint"

  name              = "${var.project}-${var.env}-tts"
  image             = var.tts_image
  workers_min       = 0 # scale-to-zero
  workers_max       = var.tts_workers_max
  container_disk_gb = 15

  env = {
    LANG_CODE              = "a"
    CALLBACK_SHARED_SECRET = var.callback_shared_secret
  }
}

module "bg_audio" {
  source = "../../modules/gpu_endpoint"

  name              = "${var.project}-${var.env}-bg-audio"
  image             = var.bg_audio_image
  workers_min       = 0 # scale-to-zero
  workers_max       = var.bg_audio_workers_max
  container_disk_gb = 20

  env = {
    MODEL_ID               = "stabilityai/stable-audio-open-1.0"
    CALLBACK_SHARED_SECRET = var.callback_shared_secret
  }
}

module "lip_sync" {
  source = "../../modules/gpu_endpoint"

  name              = "${var.project}-${var.env}-lip-sync"
  image             = var.lip_sync_image
  workers_min       = 0 # scale-to-zero
  workers_max       = var.lip_sync_workers_max
  container_disk_gb = 40 # MuseTalk's baked-in weights + MMLab stack are heavy

  env = {
    CALLBACK_SHARED_SECRET = var.callback_shared_secret
  }
}
