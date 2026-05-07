# demo-pr-gate: intentional violations for gate demo
#
# Violation 1 — S3 public access disabled
#   Caught by: Checkov (CKV_AWS_53/54/55/56, CKV2_AWS_6)
#   Mirrors:   s3_remediation.py → block_public_access()
#
# Violation 2 — IAM wildcard Action+Resource
#   Caught by: OPA iam.rego (Checkov skips CKV_AWS_355 — OPA closes the gap)
#   Mirrors:   iam_remediation.py → is_dangerous_wildcard_action()

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

resource "aws_iam_policy" "demo_wildcard" {
  name        = "demo-wildcard-policy"
  description = "Demo — intentional wildcard violation for PR gate"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WildcardAdmin"
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
