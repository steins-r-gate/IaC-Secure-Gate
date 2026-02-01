# ==================================================================
# Self-Improvement Module - Local Variables
# terraform/modules/self-improvement/locals.tf
# ==================================================================

locals {
  # Resource naming prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # SNS topic names
  remediation_alerts_topic_name  = "${local.name_prefix}-remediation-alerts"
  analytics_reports_topic_name   = "${local.name_prefix}-analytics-reports"
  manual_review_topic_name       = "${local.name_prefix}-manual-review"

  # Lambda naming
  analytics_lambda_name = "${local.name_prefix}-analytics"

  # Module-specific tags
  module_tags = merge(var.common_tags, {
    Module    = "self-improvement"
    Component = "Notifications"
  })

  # Analytics specific tags
  analytics_tags = merge(var.common_tags, {
    Module    = "self-improvement"
    Component = "Analytics"
  })
}
