# phase3-evidence: IAM wildcard policy — intentional violation
# Blocked by: OPA policies/opa/iam.rego (deny - Action=* on Resource=*)
# Note: Checkov CKV_AWS_355 and CKV_AWS_290 are skip-listed in .checkov.yml
#       OPA closes this gap — commit-time enforcement mirrors Phase 2 iam_remediation.py
resource "aws_iam_policy" "phase3_evidence_iam_wildcard" {
  name        = "phase3-evidence-iam-wildcard"
  description = "Phase 3 evidence test — intentional wildcard violation"

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
