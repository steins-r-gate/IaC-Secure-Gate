# ==================================================================
# Slack Integration Module - Outputs
# terraform/modules/slack-integration/outputs.tf
# ==================================================================

output "api_gateway_url" {
  description = "API Gateway callback URL for Slack interactivity"
  value       = "${aws_api_gateway_stage.slack_callback.invoke_url}/v1/callback"
}

output "slack_notifier_function_arn" {
  description = "ARN of the Slack notifier Lambda function"
  value       = aws_lambda_function.slack_notifier.arn
}

output "slack_notifier_function_name" {
  description = "Name of the Slack notifier Lambda function"
  value       = aws_lambda_function.slack_notifier.function_name
}

output "slack_callback_function_arn" {
  description = "ARN of the Slack callback Lambda function"
  value       = aws_lambda_function.slack_callback.arn
}

output "ci_gate_notifier_function_arn" {
  description = "ARN of the CI gate notifier Lambda function"
  value       = aws_lambda_function.ci_gate_notifier.arn
}

output "ci_gate_notifier_function_name" {
  description = "Name of the CI gate notifier Lambda function"
  value       = aws_lambda_function.ci_gate_notifier.function_name
}
