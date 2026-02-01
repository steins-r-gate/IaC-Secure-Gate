# ==================================================================
# EventBridge Remediation Module - Local Variables
# terraform/modules/eventbridge-remediation/locals.tf
# ==================================================================

locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # Module-specific tags
  eventbridge_tags = merge(var.common_tags, {
    Module  = "eventbridge-remediation"
    Service = "Amazon-EventBridge"
    Phase   = "Phase-2-Remediation"
  })

  # Rule names
  iam_rule_name = "${local.name_prefix}-iam-wildcard-remediation"
  s3_rule_name  = "${local.name_prefix}-s3-public-remediation"
  sg_rule_name  = "${local.name_prefix}-sg-open-remediation"
}
