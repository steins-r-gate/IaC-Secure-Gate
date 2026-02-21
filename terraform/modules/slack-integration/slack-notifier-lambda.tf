# ==================================================================
# Slack Notifier Lambda
# terraform/modules/slack-integration/slack-notifier-lambda.tf
# Purpose: Sends interactive Block Kit messages to Slack
# ==================================================================

# ----------------------------------------------------------------------
# Lambda Package
# ----------------------------------------------------------------------

data "archive_file" "slack_notifier" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/slack_notifier.py"
  output_path = "${path.module}/dist/slack_notifier.zip"
}

# ----------------------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "slack_notifier" {
  name              = "/aws/lambda/${local.slack_notifier_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.module_tags, {
    Name     = "${local.slack_notifier_name}-logs"
    Function = "slack-notifier"
  })
}

# ----------------------------------------------------------------------
# IAM Role
# ----------------------------------------------------------------------

resource "aws_iam_role" "slack_notifier" {
  name        = "${local.slack_notifier_name}-role"
  description = "Execution role for Slack notifier Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(local.module_tags, {
    Name     = "${local.slack_notifier_name}-role"
    Function = "slack-notifier"
  })
}

resource "aws_iam_role_policy" "slack_notifier_logs" {
  name = "${local.slack_notifier_name}-logs-policy"
  role = aws_iam_role.slack_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.slack_notifier.arn}",
          "${aws_cloudwatch_log_group.slack_notifier.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "slack_notifier_ssm" {
  name = "${local.slack_notifier_name}-ssm-policy"
  role = aws_iam_role.slack_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = aws_ssm_parameter.slack_bot_token.arn
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------

resource "aws_lambda_function" "slack_notifier" {
  function_name = local.slack_notifier_name
  description   = "Sends interactive Slack messages for HITL approval workflows"

  filename         = data.archive_file.slack_notifier.output_path
  source_code_hash = data.archive_file.slack_notifier.output_base64sha256
  handler          = "slack_notifier.lambda_handler"
  runtime          = var.lambda_runtime

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.slack_notifier.arn

  environment {
    variables = {
      ENVIRONMENT           = var.environment
      PROJECT_NAME          = var.project_name
      SLACK_CHANNEL_ID      = var.slack_channel_id
      SLACK_BOT_TOKEN_PARAM = aws_ssm_parameter.slack_bot_token.name
      LOG_LEVEL             = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.slack_notifier,
    aws_iam_role_policy.slack_notifier_logs
  ]

  tags = merge(local.module_tags, {
    Name     = local.slack_notifier_name
    Function = "slack-notifier"
  })
}
