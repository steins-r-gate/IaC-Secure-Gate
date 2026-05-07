# demo-pr-gate: intentional violations for gate demo
#
# Violation 1 — S3 public access disabled
#   Caught by: Checkov (CKV_AWS_53/54/55/56, CKV2_AWS_6)
#   Mirrors:   s3_remediation.py → block_public_access()
#
# Violation 2 — DynamoDB with PROVISIONED billing
#   Caught by: OPA cost_guard.rego (billing_mode == "PROVISIONED" exceeds budget)
#   Simple attribute check — no JSON parsing required

resource "aws_s3_bucket" "demo_insecure" {
  bucket        = "demo-insecure-bucket-pr-gate"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "demo_insecure" {
  bucket                  = aws_s3_bucket.demo_insecure.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_dynamodb_table" "demo_expensive" {
  name           = "demo-expensive-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
