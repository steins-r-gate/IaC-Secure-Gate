# demo-pr-gate: S3 public access disabled — intentional violation for demo
# Mirrors the violation that Phase 2 s3_remediation.py remediates at runtime.
# Checkov rules expected to fire: CKV_AWS_53, CKV_AWS_54, CKV_AWS_55,
#   CKV_AWS_56, CKV2_AWS_6, CKV2_AWS_61, CKV_AWS_21, CKV_AWS_19
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
