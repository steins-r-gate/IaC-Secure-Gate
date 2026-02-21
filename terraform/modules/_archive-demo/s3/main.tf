# ==================================================================
# Terraform module for S3 bucket - DEMO VERSION
# terraform/modules/s3/main.tf
# ==================================================================

locals {
  bucket_name = "iam-security-${var.environment}-demo-${var.account_id}"
}

# ============================================================================
# Demo S3 Bucket - Production-ready but simplified
# ============================================================================
resource "aws_s3_bucket" "demo" {
  bucket = local.bucket_name

  tags = merge(var.common_tags, {
    Name    = "IAM-Secure-Gate Demo Bucket"
    Service = "S3-Demo"
    Purpose = "Commission Demo"
  })
}

# Enable versioning (best practice)
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable default encryption (best practice)
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Using AWS-managed keys (simpler than KMS)
    }
    bucket_key_enabled = true
  }
}

# Block all public access (security best practice)
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule for cost optimization (optional - commented out for demo)
# resource "aws_s3_bucket_lifecycle_configuration" "demo" {
#   bucket = aws_s3_bucket.demo.id
#
#   rule {
#     id     = "archive-old-objects"
#     status = "Enabled"
#
#     transition {
#       days          = 90
#       storage_class = "STANDARD_IA"
#     }
#
#     expiration {
#       days = 365
#     }
#   }
# }

# Enforce bucket ownership (best practice)
resource "aws_s3_bucket_ownership_controls" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Bucket policy to enforce HTTPS only
resource "aws_s3_bucket_policy" "demo" {
  bucket = aws_s3_bucket.demo.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.demo.arn,
          "${aws_s3_bucket.demo.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ============================================================================
# OPTIONAL: Additional buckets for full system (commented out for demo)
# ============================================================================

# Uncomment these sections when ready to expand beyond demo:

# # KMS Key
# resource "aws_kms_key" "s3" {
#   description             = "KMS key for S3 encryption"
#   deletion_window_in_days = 10
#   enable_key_rotation     = true
#   
#   tags = merge(var.common_tags, {
#     Name = "iam-security-${var.environment}-s3-kms"
#   })
# }

# # CloudTrail Bucket
# resource "aws_s3_bucket" "cloudtrail" {
#   bucket = "iam-security-${var.environment}-cloudtrail-${var.account_id}"
#   tags   = merge(var.common_tags, { Name = "CloudTrail Logs" })
# }

# # Config Bucket
# resource "aws_s3_bucket" "config" {
#   bucket = "iam-security-${var.environment}-config-${var.account_id}"
#   tags   = merge(var.common_tags, { Name = "Config Logs" })
# }
