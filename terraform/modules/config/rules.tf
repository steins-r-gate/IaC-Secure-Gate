# ==================================================================
# AWS Config Module - Config Rules
# terraform/modules/config/rules.tf
# Purpose: Deploy AWS Config managed rules for CIS compliance
# ==================================================================

locals {
  # Default CIS AWS Foundations Benchmark rules
  default_config_rules = {
    root-account-mfa-enabled = {
      description       = "Checks whether MFA is enabled for root user (CIS 1.5)"
      source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
      input_parameters  = {}
    }
    iam-password-policy = {
      description       = "Checks IAM password policy meets CIS requirements (CIS 1.8-1.11)"
      source_identifier = "IAM_PASSWORD_POLICY"
      input_parameters = {
        RequireUppercaseCharacters = "true"
        RequireLowercaseCharacters = "true"
        RequireSymbols             = "true"
        RequireNumbers             = "true"
        MinimumPasswordLength      = "14"
        PasswordReusePrevention    = "24"
        MaxPasswordAge             = "90"
      }
    }
    access-keys-rotated = {
      description       = "Checks if IAM access keys are rotated within 90 days (CIS 1.14)"
      source_identifier = "ACCESS_KEYS_ROTATED"
      input_parameters = {
        maxAccessKeyAge = "90"
      }
    }
    iam-user-mfa-enabled = {
      description       = "Checks if MFA is enabled for IAM users with console access (CIS 1.10)"
      source_identifier = "IAM_USER_MFA_ENABLED"
      input_parameters  = {}
    }
    cloudtrail-enabled = {
      description       = "Checks if CloudTrail is enabled in all regions (CIS 3.1)"
      source_identifier = "CLOUD_TRAIL_ENABLED"
      input_parameters  = {}
    }
    cloudtrail-log-file-validation-enabled = {
      description       = "Checks if CloudTrail log file validation is enabled (CIS 3.2)"
      source_identifier = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
      input_parameters  = {}
    }
    s3-bucket-public-read-prohibited = {
      description       = "Checks S3 buckets do not allow public read access (CIS 2.3.1)"
      source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
      input_parameters  = {}
    }
    s3-bucket-public-write-prohibited = {
      description       = "Checks S3 buckets do not allow public write access (CIS 2.3.1)"
      source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
      input_parameters  = {}
    }
  }

  # Use custom rules if provided, otherwise use defaults
  config_rules_to_deploy = var.config_rules != null ? var.config_rules : local.default_config_rules
}

# ==================================================================
# AWS Config Rules - CIS AWS Foundations Benchmark
# ==================================================================

resource "aws_config_config_rule" "rules" {
  for_each = var.enable_config_rules ? local.config_rules_to_deploy : {}

  name        = each.key
  description = each.value.description

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  # Only add input_parameters if they exist and are not empty
  input_parameters = length(each.value.input_parameters) > 0 ? jsonencode(each.value.input_parameters) : null

  # CRITICAL: Rules must depend on recorder being STARTED (enabled state)
  # not just the recorder resource existing
  depends_on = [
    aws_config_configuration_recorder_status.main
  ]

  tags = merge(local.config_tags, {
    Name      = each.key
    Benchmark = "CIS-AWS-Foundations"
  })
}
