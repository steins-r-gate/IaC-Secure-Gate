# ==================================================================
# Step Functions HITL Module - Outputs
# terraform/modules/step-functions-hitl/outputs.tf
# ==================================================================

output "state_machine_arn" {
  description = "ARN of the HITL orchestrator state machine"
  value       = aws_sfn_state_machine.hitl_orchestrator.arn
}

output "state_machine_name" {
  description = "Name of the HITL orchestrator state machine"
  value       = aws_sfn_state_machine.hitl_orchestrator.name
}

output "sfn_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.sfn_execution.arn
}

output "triage_lambda_arn" {
  description = "ARN of the finding triage Lambda function"
  value       = aws_lambda_function.finding_triage.arn
}
