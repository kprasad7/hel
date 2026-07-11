output "submit_job_lambda_arn" {
  value = aws_lambda_function.submit_job.arn
}

output "get_job_lambda_arn" {
  value = aws_lambda_function.get_job.arn
}

output "runpod_callback_lambda_arn" {
  value = aws_lambda_function.runpod_callback.arn
}
