# ==================================================================
# Lambda Remediation Module - Outputs
# terraform/modules/lambda-remediation/outputs.tf
# ==================================================================

# ==================================================================
# IAM Remediation Lambda Outputs
# ==================================================================

output "iam_remediation_function_name" {
  description = "IAM remediation Lambda function name"
  value       = var.enable_iam_remediation ? aws_lambda_function.iam_remediation[0].function_name : null
}

output "iam_remediation_function_arn" {
  description = "IAM remediation Lambda function ARN"
  value       = var.enable_iam_remediation ? aws_lambda_function.iam_remediation[0].arn : null
}

output "iam_remediation_invoke_arn" {
  description = "IAM remediation Lambda invoke ARN (for EventBridge)"
  value       = var.enable_iam_remediation ? aws_lambda_function.iam_remediation[0].invoke_arn : null
}

output "iam_remediation_role_arn" {
  description = "IAM remediation Lambda execution role ARN"
  value       = var.enable_iam_remediation ? aws_iam_role.iam_remediation[0].arn : null
}

output "iam_remediation_log_group_name" {
  description = "IAM remediation CloudWatch Log Group name"
  value       = var.enable_iam_remediation ? aws_cloudwatch_log_group.iam_remediation[0].name : null
}

output "iam_remediation_dlq_arn" {
  description = "IAM remediation Dead Letter Queue ARN"
  value       = var.enable_iam_remediation && var.enable_dead_letter_queue ? aws_sqs_queue.iam_remediation_dlq[0].arn : null
}

output "iam_remediation_dlq_url" {
  description = "IAM remediation Dead Letter Queue URL"
  value       = var.enable_iam_remediation && var.enable_dead_letter_queue ? aws_sqs_queue.iam_remediation_dlq[0].url : null
}

# ==================================================================
# S3 Remediation Lambda Outputs
# ==================================================================

output "s3_remediation_function_name" {
  description = "S3 remediation Lambda function name"
  value       = var.enable_s3_remediation ? aws_lambda_function.s3_remediation[0].function_name : null
}

output "s3_remediation_function_arn" {
  description = "S3 remediation Lambda function ARN"
  value       = var.enable_s3_remediation ? aws_lambda_function.s3_remediation[0].arn : null
}

output "s3_remediation_invoke_arn" {
  description = "S3 remediation Lambda invoke ARN (for EventBridge)"
  value       = var.enable_s3_remediation ? aws_lambda_function.s3_remediation[0].invoke_arn : null
}

output "s3_remediation_role_arn" {
  description = "S3 remediation Lambda execution role ARN"
  value       = var.enable_s3_remediation ? aws_iam_role.s3_remediation[0].arn : null
}

output "s3_remediation_log_group_name" {
  description = "S3 remediation CloudWatch Log Group name"
  value       = var.enable_s3_remediation ? aws_cloudwatch_log_group.s3_remediation[0].name : null
}

output "s3_remediation_dlq_arn" {
  description = "S3 remediation Dead Letter Queue ARN"
  value       = var.enable_s3_remediation && var.enable_dead_letter_queue ? aws_sqs_queue.s3_remediation_dlq[0].arn : null
}

# ==================================================================
# Security Group Remediation Lambda Outputs
# ==================================================================

output "sg_remediation_function_name" {
  description = "Security Group remediation Lambda function name"
  value       = var.enable_sg_remediation ? aws_lambda_function.sg_remediation[0].function_name : null
}

output "sg_remediation_function_arn" {
  description = "Security Group remediation Lambda function ARN"
  value       = var.enable_sg_remediation ? aws_lambda_function.sg_remediation[0].arn : null
}

output "sg_remediation_invoke_arn" {
  description = "Security Group remediation Lambda invoke ARN (for EventBridge)"
  value       = var.enable_sg_remediation ? aws_lambda_function.sg_remediation[0].invoke_arn : null
}

output "sg_remediation_role_arn" {
  description = "Security Group remediation Lambda execution role ARN"
  value       = var.enable_sg_remediation ? aws_iam_role.sg_remediation[0].arn : null
}

output "sg_remediation_log_group_name" {
  description = "Security Group remediation CloudWatch Log Group name"
  value       = var.enable_sg_remediation ? aws_cloudwatch_log_group.sg_remediation[0].name : null
}

output "sg_remediation_dlq_arn" {
  description = "Security Group remediation Dead Letter Queue ARN"
  value       = var.enable_sg_remediation && var.enable_dead_letter_queue ? aws_sqs_queue.sg_remediation_dlq[0].arn : null
}

# ==================================================================
# Module Summary
# ==================================================================

output "remediation_summary" {
  description = "Summary of Lambda remediation module configuration"
  value = {
    # Environment
    environment = var.environment
    project     = var.project_name
    region      = data.aws_region.current.id
    account_id  = data.aws_caller_identity.current.account_id

    # Lambda Configuration
    runtime       = var.lambda_runtime
    timeout       = var.lambda_timeout
    memory_size   = var.lambda_memory_size
    log_retention = var.lambda_log_retention_days

    # Feature Flags
    iam_remediation_enabled = var.enable_iam_remediation
    s3_remediation_enabled  = var.enable_s3_remediation
    sg_remediation_enabled  = var.enable_sg_remediation
    dlq_enabled             = var.enable_dead_letter_queue
    dry_run_mode            = var.dry_run_mode

    # Functions Deployed
    functions_deployed = compact([
      var.enable_iam_remediation ? "iam-remediation" : null,
      var.enable_s3_remediation ? "s3-remediation" : null,
      var.enable_sg_remediation ? "sg-remediation" : null
    ])

    # Integration Points
    dynamodb_configured = var.enable_dynamodb_logging
    sns_configured      = var.enable_sns_notifications

    # Cost Estimate (monthly, within free tier)
    monthly_cost_estimate = "$0.00 (Lambda free tier: 1M requests/month)"
  }
}
