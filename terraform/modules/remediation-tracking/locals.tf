# ==================================================================
# Remediation Tracking Module - Local Variables
# terraform/modules/remediation-tracking/locals.tf
# ==================================================================

locals {
  # Resource naming prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # DynamoDB table name
  table_name = "${local.name_prefix}-${var.table_name_suffix}"

  # Module-specific tags
  module_tags = merge(var.common_tags, {
    Module    = "remediation-tracking"
    Component = "DynamoDB"
  })

  # Current timestamp for documentation
  current_time = timestamp()
}
