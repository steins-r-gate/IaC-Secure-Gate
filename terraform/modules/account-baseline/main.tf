# ==================================================================
# Account Baseline Module - Account-Level Security Settings
# terraform/modules/account-baseline/main.tf
# Purpose: CIS compliance for S3.1, EC2.7, IAM.15
# ==================================================================

# ==================================================================
# S3.1 — Account-Level S3 Block Public Access
# ==================================================================

resource "aws_s3_account_public_access_block" "this" {
  count = var.enable_s3_account_bpa ? 1 : 0

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==================================================================
# EC2.7 — EBS Default Encryption
# ==================================================================

resource "aws_ebs_encryption_by_default" "this" {
  count   = var.enable_ebs_default_encryption ? 1 : 0
  enabled = true
}

# ==================================================================
# IAM.15 — IAM Password Policy
# ==================================================================

resource "aws_iam_account_password_policy" "this" {
  count = var.enable_password_policy ? 1 : 0

  minimum_password_length        = var.password_minimum_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  max_password_age               = var.password_max_age_days
  password_reuse_prevention      = var.password_reuse_prevention
  allow_users_to_change_password = true
}
