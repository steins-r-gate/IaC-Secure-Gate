# ==================================================================
# Foundation Module - CloudTrail S3 Bucket
# terraform/modules/foundation/s3_cloudtrail.tf
# Purpose: Secure S3 bucket for CloudTrail logs with CIS compliance
# ==================================================================

# ==================================================================
# S3 Bucket
# ==================================================================

resource "aws_s3_bucket" "cloudtrail" {
  bucket = local.cloudtrail_bucket_name

  # Object Lock requires this to be set at bucket creation
  object_lock_enabled = var.enable_object_lock

  tags = local.cloudtrail_tags
}

# ==================================================================
# Versioning (REQUIRED for CIS 3.7)
# ==================================================================

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ==================================================================
# Server-Side Encryption with KMS (REQUIRED for CIS 3.6)
# ==================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

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

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==================================================================
# Ownership Controls - BucketOwnerEnforced (CIS 2.1.5.1)
# ==================================================================

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  # Ensure public access block is applied first
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# ==================================================================
# Lifecycle Policy - Cost Optimization + Noncurrent Version Management
# ==================================================================

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  # Rule 1: Current version lifecycle
  rule {
    id     = "cloudtrail-current-version-lifecycle"
    status = "Enabled"

    filter {}

    # Move to Glacier after configured days
    transition {
      days          = var.cloudtrail_glacier_transition_days
      storage_class = "GLACIER"
    }

    # Delete after retention period
    expiration {
      days = var.cloudtrail_log_retention_days
    }
  }

  # Rule 2: Noncurrent version lifecycle (CRITICAL - missing in original)
  # Manages old versions created by versioning to prevent unbounded storage costs
  rule {
    id     = "cloudtrail-noncurrent-version-cleanup"
    status = "Enabled"

    filter {}

    # Transition old versions to Glacier faster than current
    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "GLACIER"
    }

    # Delete old versions after shorter retention
    noncurrent_version_expiration {
      noncurrent_days = var.cloudtrail_noncurrent_version_retention_days
    }
  }

  # Rule 3: Delete markers cleanup (CRITICAL - missing in original)
  # Removes delete markers when all versions are expired (keeps bucket clean)
  rule {
    id     = "cloudtrail-delete-marker-cleanup"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  # Rule 4: Abort incomplete multipart uploads (COST OPTIMIZATION)
  # Cleans up failed uploads that consume storage without being visible
  rule {
    id     = "cloudtrail-abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail]
}

# ==================================================================
# Object Lock Configuration (OPTIONAL - WORM for immutable logs)
# ==================================================================

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  count = var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail]
}

# ==================================================================
# Bucket Logging (OPTIONAL - S3 access logs)
# ==================================================================

resource "aws_s3_bucket_logging" "cloudtrail" {
  count = var.enable_bucket_logging ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail.id

  target_bucket = var.bucket_logging_target_bucket
  target_prefix = "${var.bucket_logging_target_prefix}cloudtrail/"
}

# ==================================================================
# Bucket Policy - Least Privilege with Proper Conditions
# ==================================================================

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
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
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*"
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
      "${aws_s3_bucket.cloudtrail.arn}/*"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # Statement 3: Deny wrong KMS key
  # Ensures CloudTrail uses OUR KMS key, not a different one
  statement {
    sid    = "DenyIncorrectEncryptionHeader"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/*"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.logs.arn]
    }
  }

  # Statement 4: CloudTrail ACL check
  # CloudTrail needs this to verify it can write to bucket
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    # SECURITY: Restrict to your account's CloudTrail only
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Statement 5: CloudTrail write access
  # CRITICAL: This is the core permission allowing CloudTrail to write logs
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
    ]

    # SECURITY: Restrict to your account's CloudTrail only
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    # SECURITY: Restrict to CloudTrail trails in your account
    # This prevents other AWS accounts from writing to your bucket
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/*"
      ]
    }

    # COMPATIBILITY NOTE: Removed s3:x-amz-acl condition
    # BucketOwnerEnforced disables ACLs, so this condition would fail
    # Bucket ownership is now automatic without ACL header
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json

  # CRITICAL: Apply policy AFTER ownership controls and public access block
  # Otherwise policy might be rejected
  depends_on = [
    aws_s3_bucket_public_access_block.cloudtrail,
    aws_s3_bucket_ownership_controls.cloudtrail
  ]
}
