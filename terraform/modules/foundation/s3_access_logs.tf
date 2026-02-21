# ==================================================================
# Foundation Module - S3 Access Logs Bucket
# terraform/modules/foundation/s3_access_logs.tf
# Purpose: Dedicated bucket for S3 access logging (CloudTrail.7)
# ==================================================================

# ==================================================================
# Access Logs Bucket (created when bucket logging is enabled
# and no external target bucket is provided)
# ==================================================================

locals {
  # Create internal access logs bucket when logging is enabled and no external target is specified
  create_access_logs_bucket = var.enable_bucket_logging && var.bucket_logging_target_bucket == null

  access_logs_bucket_name = "${var.project_name}-${var.environment}-access-logs-${local.account_id}"

  # Resolve the actual logging target bucket
  logging_target_bucket = local.create_access_logs_bucket ? aws_s3_bucket.access_logs[0].id : var.bucket_logging_target_bucket
}

resource "aws_s3_bucket" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = local.access_logs_bucket_name

  tags = merge(local.foundation_tags, {
    Name    = "S3 Access Logs Bucket"
    Service = "S3-Access-Logging"
  })
}

# ==================================================================
# SSE-S3 Encryption (NOT KMS — S3 access logging doesn't support KMS destinations)
# ==================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ==================================================================
# Public Access Block
# ==================================================================

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==================================================================
# Versioning
# ==================================================================

resource "aws_s3_bucket_versioning" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ==================================================================
# Ownership Controls — BucketOwnerPreferred (required for S3 log delivery)
# ==================================================================

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

# ==================================================================
# Lifecycle — 90-day expiration
# ==================================================================

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "access-logs-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }

  rule {
    id     = "access-logs-abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.access_logs]
}

# ==================================================================
# Bucket Policy — Allow S3 logging service to write + deny insecure transport
# ==================================================================

data "aws_iam_policy_document" "access_logs_bucket_policy" {
  count = local.create_access_logs_bucket ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs[0].arn,
      "${aws_s3_bucket.access_logs[0].arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowS3LogDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs[0].arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = local.create_access_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs_bucket_policy[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.access_logs,
    aws_s3_bucket_ownership_controls.access_logs
  ]
}
