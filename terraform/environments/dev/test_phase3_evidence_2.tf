# phase3-evidence: S3 public access block disabled — intentional violation
# Blocked by: Checkov CKV_AWS_53/54/55/56 + OPA policies/opa/s3.rego (deny)
# Mirrors Phase 2 s3_remediation.py block_public_access() at commit time
resource "aws_s3_bucket" "phase3_evidence_s3_public" {
  bucket        = "phase3-evidence-s3-public-test"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "phase3_evidence_s3_public" {
  bucket                  = aws_s3_bucket.phase3_evidence_s3_public.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}
