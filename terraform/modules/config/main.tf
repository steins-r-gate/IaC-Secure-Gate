# ==================================================================
# AWS Config Module - Main Resources
# terraform/modules/config/main.tf
# Purpose: Enable AWS Config for continuous compliance monitoring
# ==================================================================

locals {
  config_name = "${var.project_name}-${var.environment}-config"

  # Common tags for all Config resources
  config_tags = merge(var.common_tags, {
    Module  = "config"
    Service = "AWS-Config"
  })
}

# ==================================================================
# IAM Role for AWS Config
# ==================================================================

# Trust policy allowing Config service to assume this role
data "aws_iam_policy_document" "config_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM Role for Config service
resource "aws_iam_role" "config" {
  name               = "${local.config_name}-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
  description        = "Service role for AWS Config recorder"

  tags = merge(local.config_tags, {
    Name = "${local.config_name}-role"
  })
}

# Attach AWS managed policy for Config
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# Additional policy for S3 bucket access
resource "aws_iam_role_policy" "config_s3" {
  name = "${local.config_name}-s3-policy"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          var.config_bucket_arn,
          "${var.config_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ==================================================================
# AWS Config Recorder
# ==================================================================

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.config_name}-recorder"
  role_arn = aws_iam_role.config.arn

  # Record all supported resources including global (IAM)
  recording_group {
    all_supported                 = true
    include_global_resource_types = true # CIS 3.5
  }
}

# ==================================================================
# Config Delivery Channel
# ==================================================================

resource "aws_config_delivery_channel" "main" {
  name           = "${local.config_name}-delivery"
  s3_bucket_name = var.config_bucket_name

  # Daily snapshots
  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# ==================================================================
# Start Config Recorder
# ==================================================================

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ==================================================================
# AWS Config Rules - CIS AWS Foundations Benchmark
# ==================================================================

# Rule 1: Root account MFA (CIS 1.5)
resource "aws_config_config_rule" "root_mfa_enabled" {
  name        = "root-account-mfa-enabled"
  description = "Checks whether MFA is enabled for root user (CIS 1.5)"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 2: IAM password policy (CIS 1.8-1.11)
resource "aws_config_config_rule" "iam_password_policy" {
  name        = "iam-password-policy"
  description = "Checks IAM password policy meets CIS requirements"

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  # CIS requirements
  input_parameters = jsonencode({
    RequireUppercaseCharacters = true
    RequireLowercaseCharacters = true
    RequireSymbols             = true
    RequireNumbers             = true
    MinimumPasswordLength      = 14
    PasswordReusePrevention    = 24
    MaxPasswordAge             = 90
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 3: Access keys rotated (CIS 1.14)
resource "aws_config_config_rule" "access_keys_rotated" {
  name        = "access-keys-rotated"
  description = "Checks if IAM access keys are rotated within 90 days (CIS 1.14)"

  source {
    owner             = "AWS"
    source_identifier = "ACCESS_KEYS_ROTATED"
  }

  input_parameters = jsonencode({
    maxAccessKeyAge = 90
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 4: IAM user MFA (CIS 1.10)
resource "aws_config_config_rule" "iam_user_mfa_enabled" {
  name        = "iam-user-mfa-enabled"
  description = "Checks if MFA is enabled for IAM users with console access (CIS 1.10)"

  source {
    owner             = "AWS"
    source_identifier = "IAM_USER_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 5: CloudTrail enabled (CIS 3.1)
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name        = "cloudtrail-enabled"
  description = "Checks if CloudTrail is enabled in all regions (CIS 3.1)"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 6: CloudTrail log validation (CIS 3.2)
resource "aws_config_config_rule" "cloudtrail_log_file_validation" {
  name        = "cloudtrail-log-file-validation-enabled"
  description = "Checks if CloudTrail log file validation is enabled (CIS 3.2)"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 7: S3 public read prohibited (CIS 2.3.1)
resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name        = "s3-bucket-public-read-prohibited"
  description = "Checks S3 buckets do not allow public read access (CIS 2.3.1)"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# Rule 8: S3 public write prohibited (CIS 2.3.1)
resource "aws_config_config_rule" "s3_bucket_public_write_prohibited" {
  name        = "s3-bucket-public-write-prohibited"
  description = "Checks S3 buckets do not allow public write access (CIS 2.3.1)"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}
