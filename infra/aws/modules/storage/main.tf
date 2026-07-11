resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-${var.env}-jobs-artifacts"
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-intermediate-artifacts"
    status = "Enabled"
    filter {}
    expiration {
      days = var.artifacts_expiration_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = ["*"] # RunPod workers PUT here via presigned URL from any egress IP
    allowed_headers = ["*"]
  }
}

resource "aws_s3_bucket" "final" {
  bucket = "${var.project}-${var.env}-jobs-final"
}

resource "aws_s3_bucket_public_access_block" "final" {
  bucket                  = aws_s3_bucket.final.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "ui_static" {
  bucket = "${var.project}-${var.env}-ui-static"
}

resource "aws_s3_bucket_public_access_block" "ui_static" {
  bucket                  = aws_s3_bucket.ui_static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
