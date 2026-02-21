# ==================================================================
# EventBridge Remediation Module - Outputs
# terraform/modules/eventbridge-remediation/outputs.tf
# ==================================================================

# ==================================================================
# IAM Rule Outputs
# ==================================================================

output "iam_rule_name" {
  description = "Name of the IAM wildcard remediation EventBridge rule"
  value       = var.enable_iam_rule ? aws_cloudwatch_event_rule.iam_wildcard[0].name : null
}

output "iam_rule_arn" {
  description = "ARN of the IAM wildcard remediation EventBridge rule"
  value       = var.enable_iam_rule ? aws_cloudwatch_event_rule.iam_wildcard[0].arn : null
}

# ==================================================================
# S3 Rule Outputs
# ==================================================================

output "s3_rule_name" {
  description = "Name of the S3 public bucket remediation EventBridge rule"
  value       = var.enable_s3_rule ? aws_cloudwatch_event_rule.s3_public[0].name : null
}

output "s3_rule_arn" {
  description = "ARN of the S3 public bucket remediation EventBridge rule"
  value       = var.enable_s3_rule ? aws_cloudwatch_event_rule.s3_public[0].arn : null
}

# ==================================================================
# Security Group Rule Outputs
# ==================================================================

output "sg_rule_name" {
  description = "Name of the Security Group remediation EventBridge rule"
  value       = var.enable_sg_rule ? aws_cloudwatch_event_rule.sg_open[0].name : null
}

output "sg_rule_arn" {
  description = "ARN of the Security Group remediation EventBridge rule"
  value       = var.enable_sg_rule ? aws_cloudwatch_event_rule.sg_open[0].arn : null
}

# ==================================================================
# HITL Outputs
# ==================================================================

output "eventbridge_sfn_role_arn" {
  description = "ARN of the EventBridge-to-SFN IAM role (null if HITL disabled)"
  value       = var.enable_hitl ? aws_iam_role.eventbridge_sfn[0].arn : null
}

# ==================================================================
# Module Summary
# ==================================================================

output "eventbridge_summary" {
  description = "Summary of EventBridge remediation configuration"
  value = {
    environment = var.environment
    region      = data.aws_region.current.id
    account_id  = data.aws_caller_identity.current.account_id

    # Rules enabled
    iam_rule_enabled = var.enable_iam_rule
    s3_rule_enabled  = var.enable_s3_rule
    sg_rule_enabled  = var.enable_sg_rule

    # Rule names
    rules = compact([
      var.enable_iam_rule ? local.iam_rule_name : null,
      var.enable_s3_rule ? local.s3_rule_name : null,
      var.enable_sg_rule ? local.sg_rule_name : null
    ])

    # Retry configuration
    retry_attempts            = var.retry_attempts
    maximum_event_age_seconds = var.maximum_event_age_seconds

    # Security Hub controls monitored
    iam_controls = var.enable_iam_rule ? ["IAM.1", "IAM.21"] : []
    s3_controls  = var.enable_s3_rule ? ["S3.1", "S3.2", "S3.3", "S3.4", "S3.5", "S3.8", "S3.19"] : []
    sg_controls  = var.enable_sg_rule ? ["EC2.2", "EC2.18", "EC2.19", "EC2.21"] : []

    # Cost (EventBridge custom events)
    monthly_cost_estimate = "$0.00 (first 1M events free)"
  }
}
