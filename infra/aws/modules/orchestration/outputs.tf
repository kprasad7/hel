output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "invoke_video_gen_lambda_arn" {
  value = module.invoke_video_gen.lambda_arn
}

output "invoke_tts_lambda_arn" {
  value = module.invoke_tts.lambda_arn
}

output "invoke_bg_audio_lambda_arn" {
  value = module.invoke_bg_audio.lambda_arn
}

output "invoke_lip_sync_lambda_arn" {
  value = module.invoke_lip_sync.lambda_arn
}
