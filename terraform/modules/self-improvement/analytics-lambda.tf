# ==================================================================
# Self-Improvement Module - Analytics Lambda
# terraform/modules/self-improvement/analytics-lambda.tf
#
# Purpose: Daily analytics processing and reporting
# - Queries DynamoDB for remediation history
# - Calculates statistics and identifies patterns
# - Publishes reports via SNS
# ==================================================================

# ----------------------------------------------------------------------
# Lambda Source Code Packaging
# ----------------------------------------------------------------------

data "archive_file" "analytics" {
  count = var.enable_analytics_lambda ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/../../../lambda/src/analytics.py"
  output_path = "${path.module}/dist/analytics.zip"
}

# ----------------------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "analytics" {
  count = var.enable_analytics_lambda ? 1 : 0

  name              = "/aws/lambda/${local.analytics_lambda_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.analytics_tags, {
    Name = "${local.analytics_lambda_name}-logs"
  })
}

# ----------------------------------------------------------------------
# IAM Role for Analytics Lambda
# ----------------------------------------------------------------------

resource "aws_iam_role" "analytics" {
  count = var.enable_analytics_lambda ? 1 : 0

  name = "${local.analytics_lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.analytics_tags
}

# IAM Policy - CloudWatch Logs
resource "aws_iam_role_policy" "analytics_logs" {
  count = var.enable_analytics_lambda ? 1 : 0

  name = "${local.analytics_lambda_name}-logs-policy"
  role = aws_iam_role.analytics[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.analytics[0].arn}:*"
      }
    ]
  })
}

# IAM Policy - DynamoDB Read
resource "aws_iam_role_policy" "analytics_dynamodb" {
  count = var.enable_analytics_lambda && var.dynamodb_table_arn != "" ? 1 : 0

  name = "${local.analytics_lambda_name}-dynamodb-policy"
  role = aws_iam_role.analytics[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:GetItem"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      }
    ]
  })
}

# IAM Policy - SNS Publish
resource "aws_iam_role_policy" "analytics_sns" {
  count = var.enable_analytics_lambda && var.enable_analytics_reports ? 1 : 0

  name = "${local.analytics_lambda_name}-sns-policy"
  role = aws_iam_role.analytics[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.analytics_reports[0].arn
      }
    ]
  })
}

# ----------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------

resource "aws_lambda_function" "analytics" {
  count = var.enable_analytics_lambda ? 1 : 0

  function_name = local.analytics_lambda_name
  description   = "Analyzes remediation history and generates daily reports"

  filename         = data.archive_file.analytics[0].output_path
  source_code_hash = data.archive_file.analytics[0].output_base64sha256
  handler          = "analytics.lambda_handler"
  runtime          = "python3.12"

  role        = aws_iam_role.analytics[0].arn
  timeout     = var.analytics_lambda_timeout
  memory_size = var.analytics_lambda_memory

  environment {
    variables = {
      ENVIRONMENT    = var.environment
      LOG_LEVEL      = var.environment == "prod" ? "INFO" : "DEBUG"
      DYNAMODB_TABLE = var.dynamodb_table_name
      SNS_TOPIC_ARN  = var.enable_analytics_reports ? aws_sns_topic.analytics_reports[0].arn : ""
      ANALYSIS_DAYS  = "30"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.analytics,
    aws_iam_role_policy.analytics_logs
  ]

  tags = merge(local.analytics_tags, {
    Name = local.analytics_lambda_name
  })
}

# ----------------------------------------------------------------------
# CloudWatch Events Rule (Scheduled Trigger)
# ----------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "analytics_schedule" {
  count = var.enable_analytics_lambda ? 1 : 0

  name                = "${local.analytics_lambda_name}-schedule"
  description         = "Triggers analytics Lambda daily at 2 AM UTC"
  schedule_expression = var.analytics_schedule

  tags = local.analytics_tags
}

resource "aws_cloudwatch_event_target" "analytics_lambda" {
  count = var.enable_analytics_lambda ? 1 : 0

  rule      = aws_cloudwatch_event_rule.analytics_schedule[0].name
  target_id = "AnalyticsLambda"
  arn       = aws_lambda_function.analytics[0].arn

  input = jsonencode({
    source        = "aws.events"
    analysis_days = 30
  })
}

resource "aws_lambda_permission" "analytics_eventbridge" {
  count = var.enable_analytics_lambda ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analytics[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.analytics_schedule[0].arn
}
