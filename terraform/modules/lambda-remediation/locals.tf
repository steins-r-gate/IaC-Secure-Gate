# ==================================================================
# Lambda Remediation Module - Local Variables
# terraform/modules/lambda-remediation/locals.tf
# ==================================================================

locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # Module-specific tags
  remediation_tags = merge(var.common_tags, {
    Module  = "lambda-remediation"
    Service = "AWS-Lambda"
    Phase   = "Phase-2-Remediation"
  })

  # Lambda function names
  iam_lambda_name = "${local.name_prefix}-iam-remediation"
  s3_lambda_name  = "${local.name_prefix}-s3-remediation"
  sg_lambda_name  = "${local.name_prefix}-sg-remediation"

  # Common Lambda environment variables
  common_env_vars = {
    ENVIRONMENT    = var.environment
    PROJECT_NAME   = var.project_name
    DRY_RUN_MODE   = tostring(var.dry_run_mode)
    DYNAMODB_TABLE = var.dynamodb_table_name
    SNS_TOPIC_ARN  = var.sns_topic_arn
    AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    LOG_LEVEL      = var.environment == "prod" ? "INFO" : "DEBUG"
  }
}
