# ==================================================================
# Slack Callback Lambda
# terraform/modules/slack-integration/callback-lambda.tf
# Purpose: Receives Slack button clicks, validates signature,
#          routes to SFN (Phase 2) or DynamoDB (Phase 3)
# ==================================================================

# ----------------------------------------------------------------------
# Lambda Package
# ----------------------------------------------------------------------

data "archive_file" "slack_callback" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/slack_callback.py"
  output_path = "${path.module}/dist/slack_callback.zip"
}

# ----------------------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "slack_callback" {
  name              = "/aws/lambda/${local.slack_callback_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.module_tags, {
    Name     = "${local.slack_callback_name}-logs"
    Function = "slack-callback"
  })
}

# ----------------------------------------------------------------------
# IAM Role
# ----------------------------------------------------------------------

resource "aws_iam_role" "slack_callback" {
  name        = "${local.slack_callback_name}-role"
  description = "Execution role for Slack callback Lambda"

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
    Name     = "${local.slack_callback_name}-role"
    Function = "slack-callback"
  })
}

resource "aws_iam_role_policy" "slack_callback_logs" {
  name = "${local.slack_callback_name}-logs-policy"
  role = aws_iam_role.slack_callback.id

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
          "${aws_cloudwatch_log_group.slack_callback.arn}",
          "${aws_cloudwatch_log_group.slack_callback.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "slack_callback_ssm" {
  name = "${local.slack_callback_name}-ssm-policy"
  role = aws_iam_role.slack_callback.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          aws_ssm_parameter.slack_signing_secret.arn,
          aws_ssm_parameter.slack_bot_token.arn,
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "slack_callback_sfn" {
  name = "${local.slack_callback_name}-sfn-policy"
  role = aws_iam_role.slack_callback.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendTaskSuccess"
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        Resource = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.name_prefix}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "slack_callback_dynamodb" {
  name = "${local.slack_callback_name}-dynamodb-policy"
  role = aws_iam_role.slack_callback.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteToDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------

resource "aws_lambda_function" "slack_callback" {
  function_name = local.slack_callback_name
  description   = "Handles Slack interactive callbacks for HITL approval workflows"

  filename         = data.archive_file.slack_callback.output_path
  source_code_hash = data.archive_file.slack_callback.output_base64sha256
  handler          = "slack_callback.lambda_handler"
  runtime          = var.lambda_runtime

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.slack_callback.arn

  environment {
    variables = {
      ENVIRONMENT                = var.environment
      PROJECT_NAME               = var.project_name
      DYNAMODB_TABLE             = var.dynamodb_table_name
      SLACK_SIGNING_SECRET_PARAM = aws_ssm_parameter.slack_signing_secret.name
      SLACK_BOT_TOKEN_PARAM      = aws_ssm_parameter.slack_bot_token.name
      LOG_LEVEL                  = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.slack_callback,
    aws_iam_role_policy.slack_callback_logs
  ]

  tags = merge(local.module_tags, {
    Name     = local.slack_callback_name
    Function = "slack-callback"
  })
}
