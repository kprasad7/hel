output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}

output "artifacts_bucket_domain" {
  value = aws_s3_bucket.artifacts.bucket_regional_domain_name
}

output "final_bucket_name" {
  value = aws_s3_bucket.final.bucket
}

output "final_bucket_arn" {
  value = aws_s3_bucket.final.arn
}

output "ui_static_bucket_name" {
  value = aws_s3_bucket.ui_static.bucket
}

output "ui_static_bucket_arn" {
  value = aws_s3_bucket.ui_static.arn
}

output "ui_static_bucket_regional_domain_name" {
  value = aws_s3_bucket.ui_static.bucket_regional_domain_name
}
