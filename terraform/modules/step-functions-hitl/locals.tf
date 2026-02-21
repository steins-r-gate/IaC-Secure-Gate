# ==================================================================
# Step Functions HITL Module - Local Variables
# terraform/modules/step-functions-hitl/locals.tf
# ==================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  module_tags = merge(var.common_tags, {
    Module  = "step-functions-hitl"
    Service = "AWS-StepFunctions"
    Phase   = "Phase-HITL"
  })

  triage_lambda_name = "${local.name_prefix}-finding-triage"
  state_machine_name = "${local.name_prefix}-hitl-orchestrator"

  # Severity ordering for auto-remediate threshold
  severity_levels = {
    "CRITICAL" = 4
    "HIGH"     = 3
    "MEDIUM"   = 2
    "LOW"      = 1
  }
}
