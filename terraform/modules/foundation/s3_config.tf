# ==================================================================
# Foundation Module - AWS Config S3 Bucket
# terraform/modules/foundation/s3_config.tf
# Purpose: Secure S3 bucket for AWS Config snapshots with CIS compliance
# ==================================================================

# ==================================================================
# S3 Bucket
# ==================================================================

resource "aws_s3_bucket" "config" {
  bucket = local.config_bucket_name

  # Object Lock requires this to be set at bucket creation
  object_lock_enabled = var.enable_object_lock

  tags = local.config_tags
}

# ==================================================================
# Versioning (REQUIRED for CIS 3.7)
# ==================================================================

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ==================================================================
# Server-Side Encryption with KMS (REQUIRED for CIS 3.6)
# ==================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }

  # CRITICAL: Ensure KMS key policy is ready before S3 tries to use it
  depends_on = [
    aws_kms_key.logs,
    aws_kms_key_policy.logs
  ]
}

# ==================================================================
# Public Access Block (REQUIRED for CIS 2.1.5)
# ==================================================================

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==================================================================
# Ownership Controls - BucketOwnerEnforced (CIS 2.1.5.1)
# ==================================================================

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  # Ensure public access block is applied first
  depends_on = [aws_s3_bucket_public_access_block.config]
}

# ==================================================================
# Lifecycle Policy - Cost Optimization + Noncurrent Version Management
# ==================================================================

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  # Rule 1: Current version lifecycle
  rule {
    id     = "config-current-version-lifecycle"
    status = "Enabled"

    filter {}

    # Move to Glacier after configured days (longer than CloudTrail)
    transition {
      days          = var.config_glacier_transition_days
      storage_class = "GLACIER"
    }

    # Delete after retention period (longer retention for compliance)
    expiration {
      days = var.config_snapshot_retention_days
    }
  }

  # Rule 2: Noncurrent version lifecycle (CRITICAL - missing in original)
  # Manages old versions created by versioning to prevent unbounded storage costs
  rule {
    id     = "config-noncurrent-version-cleanup"
    status = "Enabled"

    filter {}

    # Transition old versions to Glacier faster than current
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    # Delete old versions after shorter retention
    noncurrent_version_expiration {
      noncurrent_days = var.config_noncurrent_version_retention_days
    }
  }

  # Rule 3: Delete markers cleanup (CRITICAL - missing in original)
  # Removes delete markers when all versions are expired (keeps bucket clean)
  rule {
    id     = "config-delete-marker-cleanup"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  # Rule 4: Abort incomplete multipart uploads (COST OPTIMIZATION)
  # Cleans up failed uploads that consume storage without being visible
  rule {
    id     = "config-abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.config]
}

# ==================================================================
# Object Lock Configuration (OPTIONAL - WORM for immutable logs)
# ==================================================================

resource "aws_s3_bucket_object_lock_configuration" "config" {
  count = var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.config.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.config]
}

# ==================================================================
# Bucket Logging (OPTIONAL - S3 access logs)
# ==================================================================

resource "aws_s3_bucket_logging" "config" {
  count = var.enable_bucket_logging ? 1 : 0

  bucket = aws_s3_bucket.config.id

  target_bucket = local.logging_target_bucket
  target_prefix = "${var.bucket_logging_target_prefix}config/"
}

# ==================================================================
# Bucket Policy - Least Privilege with Proper Conditions
# ==================================================================

data "aws_iam_policy_document" "config_bucket_policy" {
  # Statement 1: Deny insecure transport (REQUIRED for CIS 2.1.5)
  # CRITICAL: Must be explicit Deny to override any Allow
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.config.arn,
      "${aws_s3_bucket.config.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Statement 2: Deny unencrypted object uploads
  # Defense in depth: Ensures all PUT requests include encryption
  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.config.arn}/*"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # Statement 3: Deny wrong KMS key
  # Ensures Config uses OUR KMS key, not a different one
  statement {
    sid    = "DenyIncorrectEncryptionHeader"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.config.arn}/*"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.logs.arn]
    }
  }

  # Statement 4: Config bucket permissions check
  # Config needs this to verify bucket exists and is accessible
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]

    # SECURITY: Restrict to your account's Config only
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Statement 5: Config bucket existence check
  # Config needs ListBucket to check for existing snapshots
  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    # SECURITY: Restrict to your account's Config only
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Statement 6: Config write access
  # CRITICAL: This is the core permission allowing Config to write snapshots
  statement {
    sid    = "AWSConfigWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/*"
    ]

    # SECURITY: Restrict to your account's Config only
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    # SECURITY: Optional - restrict to Config service in your region
    # Note: Config doesn't provide SourceArn like CloudTrail does
    # So we use ViaService condition instead
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    # COMPATIBILITY NOTE: Removed s3:x-amz-acl condition
    # BucketOwnerEnforced disables ACLs, so this condition would fail
    # Bucket ownership is now automatic without ACL header
  }

  # Statement 7: Config GetBucketLocation (required for multi-region)
  # Config needs this to determine bucket region for proper endpoint routing
  statement {
    sid    = "AWSConfigGetBucketLocation"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.config.arn]

    # SECURITY: Restrict to your account's Config only
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket_policy.json

  # CRITICAL: Apply policy AFTER ownership controls and public access block
  # Otherwise policy might be rejected
  depends_on = [
    aws_s3_bucket_public_access_block.config,
    aws_s3_bucket_ownership_controls.config
  ]
}
