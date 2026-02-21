# ==================================================================
# CI Gate Notifier Lambda
# terraform/modules/slack-integration/ci-gate-notifier-lambda.tf
# Purpose: Sends CI gate approval requests to Slack,
#          writes PENDING status to DynamoDB
# ==================================================================

# ----------------------------------------------------------------------
# Lambda Package
# ----------------------------------------------------------------------

data "archive_file" "ci_gate_notifier" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/ci_gate_notifier.py"
  output_path = "${path.module}/dist/ci_gate_notifier.zip"
}

# ----------------------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ci_gate_notifier" {
  name              = "/aws/lambda/${local.ci_gate_notifier_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.module_tags, {
    Name     = "${local.ci_gate_notifier_name}-logs"
    Function = "ci-gate-notifier"
  })
}

# ----------------------------------------------------------------------
# IAM Role
# ----------------------------------------------------------------------

resource "aws_iam_role" "ci_gate_notifier" {
  name        = "${local.ci_gate_notifier_name}-role"
  description = "Execution role for CI gate notifier Lambda"

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
    Name     = "${local.ci_gate_notifier_name}-role"
    Function = "ci-gate-notifier"
  })
}

resource "aws_iam_role_policy" "ci_gate_notifier_logs" {
  name = "${local.ci_gate_notifier_name}-logs-policy"
  role = aws_iam_role.ci_gate_notifier.id

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
          "${aws_cloudwatch_log_group.ci_gate_notifier.arn}",
          "${aws_cloudwatch_log_group.ci_gate_notifier.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ci_gate_notifier_ssm" {
  name = "${local.ci_gate_notifier_name}-ssm-policy"
  role = aws_iam_role.ci_gate_notifier.id

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

resource "aws_iam_role_policy" "ci_gate_notifier_dynamodb" {
  name = "${local.ci_gate_notifier_name}-dynamodb-policy"
  role = aws_iam_role.ci_gate_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteToDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------

resource "aws_lambda_function" "ci_gate_notifier" {
  function_name = local.ci_gate_notifier_name
  description   = "Sends CI gate approval requests to Slack and tracks in DynamoDB"

  filename         = data.archive_file.ci_gate_notifier.output_path
  source_code_hash = data.archive_file.ci_gate_notifier.output_base64sha256
  handler          = "ci_gate_notifier.lambda_handler"
  runtime          = var.lambda_runtime

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.ci_gate_notifier.arn

  environment {
    variables = {
      ENVIRONMENT           = var.environment
      PROJECT_NAME          = var.project_name
      DYNAMODB_TABLE        = var.dynamodb_table_name
      SLACK_CHANNEL_ID      = var.slack_channel_id
      SLACK_BOT_TOKEN_PARAM = aws_ssm_parameter.slack_bot_token.name
      LOG_LEVEL             = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.ci_gate_notifier,
    aws_iam_role_policy.ci_gate_notifier_logs
  ]

  tags = merge(local.module_tags, {
    Name     = local.ci_gate_notifier_name
    Function = "ci-gate-notifier"
  })
}
