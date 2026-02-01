# ==================================================================
# EventBridge Remediation Rules
# terraform/modules/eventbridge-remediation/rules.tf
# Purpose: Route Security Hub findings to appropriate Lambda functions
# ==================================================================

# ==================================================================
# IAM Wildcard Policy Remediation Rule
# ==================================================================
# Matches findings for:
# - IAM.1: IAM policies should not allow full "*" administrative privileges
# - IAM.21: IAM customer managed policies should not allow wildcard actions

resource "aws_cloudwatch_event_rule" "iam_wildcard" {
  count = var.enable_iam_rule ? 1 : 0

  name        = local.iam_rule_name
  description = "Route IAM wildcard policy findings to remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        # Match NEW findings only (not updates to existing)
        Workflow = {
          Status = ["NEW"]
        }
        # Match FAILED compliance status
        Compliance = {
          Status = ["FAILED"]
        }
        # Match IAM-related findings
        Resources = {
          Type = ["AwsIamPolicy"]
        }
        # Match specific control IDs for IAM wildcard issues
        ProductFields = {
          "ControlId" = [
            "IAM.1", # Full admin privileges
            "IAM.21" # Wildcard actions in customer policies
          ]
        }
      }
    }
  })

  tags = merge(local.eventbridge_tags, {
    Name        = local.iam_rule_name
    FindingType = "IAM-Wildcard"
  })
}

resource "aws_cloudwatch_event_target" "iam_wildcard_lambda" {
  count = var.enable_iam_rule ? 1 : 0

  rule      = aws_cloudwatch_event_rule.iam_wildcard[0].name
  target_id = "IAMRemediationLambda"
  arn       = var.iam_remediation_lambda_arn

  # Retry configuration
  retry_policy {
    maximum_retry_attempts       = var.retry_attempts
    maximum_event_age_in_seconds = var.maximum_event_age_seconds
  }
}

# ==================================================================
# S3 Public Bucket Remediation Rule
# ==================================================================
# Matches findings for:
# - S3.1: S3 Block Public Access setting should be enabled
# - S3.2: S3 buckets should prohibit public read access
# - S3.3: S3 buckets should prohibit public write access
# - S3.4: S3 buckets should have server-side encryption enabled
# - S3.5: S3 buckets should require SSL
# - S3.19: S3 access points should have block public access enabled

resource "aws_cloudwatch_event_rule" "s3_public" {
  count = var.enable_s3_rule ? 1 : 0

  name        = local.s3_rule_name
  description = "Route S3 public bucket findings to remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Workflow = {
          Status = ["NEW"]
        }
        Compliance = {
          Status = ["FAILED"]
        }
        Resources = {
          Type = ["AwsS3Bucket"]
        }
        ProductFields = {
          "ControlId" = [
            "S3.1", # Block Public Access
            "S3.2", # Prohibit public read
            "S3.3", # Prohibit public write
            "S3.4", # Server-side encryption
            "S3.5", # Require SSL
            "S3.8", # Block public access at bucket level
            "S3.19" # Access points block public access
          ]
        }
      }
    }
  })

  tags = merge(local.eventbridge_tags, {
    Name        = local.s3_rule_name
    FindingType = "S3-Public"
  })
}

resource "aws_cloudwatch_event_target" "s3_public_lambda" {
  count = var.enable_s3_rule ? 1 : 0

  rule      = aws_cloudwatch_event_rule.s3_public[0].name
  target_id = "S3RemediationLambda"
  arn       = var.s3_remediation_lambda_arn

  retry_policy {
    maximum_retry_attempts       = var.retry_attempts
    maximum_event_age_in_seconds = var.maximum_event_age_seconds
  }
}

# ==================================================================
# Security Group Open Access Remediation Rule
# ==================================================================
# Matches findings for:
# - EC2.18: Security groups should only allow unrestricted incoming traffic for authorized ports
# - EC2.19: Security groups should not allow unrestricted access to high risk ports
# - EC2.2: Default security group should restrict all traffic

resource "aws_cloudwatch_event_rule" "sg_open" {
  count = var.enable_sg_rule ? 1 : 0

  name        = local.sg_rule_name
  description = "Route Security Group open access findings to remediation Lambda"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Workflow = {
          Status = ["NEW"]
        }
        Compliance = {
          Status = ["FAILED"]
        }
        Resources = {
          Type = ["AwsEc2SecurityGroup"]
        }
        ProductFields = {
          "ControlId" = [
            "EC2.2",  # Default SG restricts all traffic
            "EC2.18", # Unrestricted incoming traffic
            "EC2.19", # High risk ports unrestricted
            "EC2.21"  # Network ACLs unrestricted ingress
          ]
        }
      }
    }
  })

  tags = merge(local.eventbridge_tags, {
    Name        = local.sg_rule_name
    FindingType = "SecurityGroup-Open"
  })
}

resource "aws_cloudwatch_event_target" "sg_open_lambda" {
  count = var.enable_sg_rule ? 1 : 0

  rule      = aws_cloudwatch_event_rule.sg_open[0].name
  target_id = "SGRemediationLambda"
  arn       = var.sg_remediation_lambda_arn

  retry_policy {
    maximum_retry_attempts       = var.retry_attempts
    maximum_event_age_in_seconds = var.maximum_event_age_seconds
  }
}

# ==================================================================
# Alternative: Catch-All Rule for Testing (Disabled by Default)
# ==================================================================
# This rule can be enabled for testing to capture ALL Security Hub findings
# Useful for debugging event patterns

resource "aws_cloudwatch_event_rule" "all_findings_debug" {
  count = 0 # Set to 1 to enable for debugging

  name        = "${local.name_prefix}-all-findings-debug"
  description = "DEBUG: Capture all Security Hub findings (disabled in production)"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })

  tags = merge(local.eventbridge_tags, {
    Name    = "${local.name_prefix}-all-findings-debug"
    Purpose = "debugging"
  })
}
