# Single-table design:
#   PK "JOB#<job_id>", SK "META"             -> job status/params/output
#   PK "JOB#<job_id>", SK "PROFILE#<stage>"  -> per-stage GPU profiling record
resource "aws_dynamodb_table" "jobs" {
  name         = "${var.project}-${var.env}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
