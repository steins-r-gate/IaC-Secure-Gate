# ==================================================================
# Slack Integration Module - Local Variables
# terraform/modules/slack-integration/locals.tf
# ==================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  module_tags = merge(var.common_tags, {
    Module  = "slack-integration"
    Service = "Slack-HITL"
    Phase   = "Phase-HITL"
  })

  # Lambda function names
  slack_notifier_name   = "${local.name_prefix}-slack-notifier"
  slack_callback_name   = "${local.name_prefix}-slack-callback"
  ci_gate_notifier_name = "${local.name_prefix}-ci-gate-notifier"
}
