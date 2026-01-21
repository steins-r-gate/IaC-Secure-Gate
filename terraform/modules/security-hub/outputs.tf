# ==================================================================
# Security Hub Module - Outputs
# terraform/modules/security-hub/outputs.tf
# ==================================================================

# ==================================================================
# Core Security Hub Outputs
# ==================================================================

output "securityhub_account_id" {
  description = "Security Hub account ID"
  value       = aws_securityhub_account.main.id
}

output "securityhub_account_arn" {
  description = "Security Hub account ARN"
  value       = aws_securityhub_account.main.arn
}

# ==================================================================
# Standards Outputs
# ==================================================================

output "cis_standard_arn" {
  description = "CIS standard subscription ARN (null if not enabled)"
  value       = var.enable_cis_standard ? local.cis_standard_arn : null
}

output "foundational_standard_arn" {
  description = "Foundational standard subscription ARN (null if not enabled)"
  value       = var.enable_foundational_standard ? local.foundational_standard_arn : null
}

output "enabled_standards" {
  description = "List of enabled standards"
  value = compact([
    var.enable_cis_standard ? "CIS AWS Foundations Benchmark v${var.cis_standard_version}" : null,
    var.enable_foundational_standard ? "AWS Foundational Security Best Practices v${var.foundational_standard_version}" : null
  ])
}

# ==================================================================
# Integration Outputs
# ==================================================================

output "config_integration_arn" {
  description = "Config product integration ARN (null if not enabled)"
  value       = var.enable_config_integration ? aws_securityhub_product_subscription.config[0].arn : null
}

output "access_analyzer_integration_arn" {
  description = "Access Analyzer product integration ARN (null if not enabled)"
  value       = var.enable_access_analyzer_integration ? aws_securityhub_product_subscription.access_analyzer[0].arn : null
}

# ==================================================================
# Finding Aggregator Outputs
# ==================================================================

output "finding_aggregator_arn" {
  description = "Finding aggregator ARN (null if not enabled)"
  value       = var.enable_finding_aggregation ? aws_securityhub_finding_aggregator.main[0].id : null
}

# ==================================================================
# SNS Outputs
# ==================================================================

output "critical_findings_sns_topic_arn" {
  description = "SNS topic ARN for critical findings (null if not enabled)"
  value       = var.enable_critical_finding_notifications ? aws_sns_topic.critical_findings[0].arn : null
}

output "eventbridge_rule_arn" {
  description = "EventBridge rule ARN for critical findings (null if not enabled)"
  value       = var.enable_critical_finding_notifications ? aws_cloudwatch_event_rule.critical_findings[0].arn : null
}

# ==================================================================
# Control Configuration
# ==================================================================

output "control_configuration" {
  description = "Summary of control configuration"
  value = {
    cis_controls_available = var.enable_cis_standard ? (
      var.cis_standard_version == "3.0.0" ? 28 :
      var.cis_standard_version == "1.4.0" ? 25 :
      14 # v1.2.0
    ) : 0
    foundational_controls_available = var.enable_foundational_standard ? 200 : 0
    total_controls_available = (
      (var.enable_cis_standard ? (
        var.cis_standard_version == "3.0.0" ? 28 :
        var.cis_standard_version == "1.4.0" ? 25 :
        14
      ) : 0) +
      (var.enable_foundational_standard ? 200 : 0)
    )
    controls_manually_disabled = length(var.disabled_control_ids)
  }
}

# ==================================================================
# Structured Summary (Following established pattern)
# ==================================================================

output "securityhub_summary" {
  description = "Summary of Security Hub configuration"
  value = {
    # Environment
    environment = var.environment
    region      = data.aws_region.current.id
    account_id  = data.aws_caller_identity.current.account_id

    # Security Hub
    securityhub_enabled = true
    securityhub_arn     = aws_securityhub_account.main.arn

    # Standards
    cis_standard_enabled          = var.enable_cis_standard
    cis_standard_version          = var.cis_standard_version
    foundational_standard_enabled = var.enable_foundational_standard
    foundational_standard_version = var.foundational_standard_version
    total_standards_enabled = length(compact([
      var.enable_cis_standard ? "cis" : null,
      var.enable_foundational_standard ? "foundational" : null
    ]))

    # Integrations
    config_integration_enabled          = var.enable_config_integration
    access_analyzer_integration_enabled = var.enable_access_analyzer_integration
    cloudtrail_integration_enabled      = true # Automatic via Config

    # Features
    finding_aggregation_enabled    = var.enable_finding_aggregation
    critical_finding_notifications = var.enable_critical_finding_notifications
    disabled_control_count         = length(var.disabled_control_ids)

    # Controls
    total_controls_available = (
      (var.enable_cis_standard ? (
        var.cis_standard_version == "3.0.0" ? 28 :
        var.cis_standard_version == "1.4.0" ? 25 :
        14
      ) : 0) +
      (var.enable_foundational_standard ? 200 : 0)
    )

    # CIS Compliance
    cis_controls_supported = var.enable_cis_standard ? [
      "CIS 1.x - IAM controls (14 controls)",
      "CIS 2.x - Storage controls (8 controls)",
      "CIS 3.x - Logging controls (3 controls)"
    ] : []

    # Cost (estimated)
    monthly_cost_usd_min = 0.00 # First 10k findings free
    monthly_cost_usd_max = 5.00 # If exceed free tier
  }
}
