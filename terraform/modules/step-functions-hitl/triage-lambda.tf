# ==================================================================
# Finding Triage Lambda
# terraform/modules/step-functions-hitl/triage-lambda.tf
# Purpose: Classifies findings, checks false positive registry
# ==================================================================

# ----------------------------------------------------------------------
# Lambda Package
# ----------------------------------------------------------------------

data "archive_file" "finding_triage" {
  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/finding_triage.py"
  output_path = "${path.module}/dist/finding_triage.zip"
}

# ----------------------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "finding_triage" {
  name              = "/aws/lambda/${local.triage_lambda_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.module_tags, {
    Name     = "${local.triage_lambda_name}-logs"
    Function = "finding-triage"
  })
}

# ----------------------------------------------------------------------
# IAM Role
# ----------------------------------------------------------------------

resource "aws_iam_role" "finding_triage" {
  name        = "${local.triage_lambda_name}-role"
  description = "Execution role for finding triage Lambda"

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
    Name     = "${local.triage_lambda_name}-role"
    Function = "finding-triage"
  })
}

resource "aws_iam_role_policy" "finding_triage_logs" {
  name = "${local.triage_lambda_name}-logs-policy"
  role = aws_iam_role.finding_triage.id

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
          "${aws_cloudwatch_log_group.finding_triage.arn}",
          "${aws_cloudwatch_log_group.finding_triage.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "finding_triage_dynamodb" {
  name = "${local.triage_lambda_name}-dynamodb-policy"
  role = aws_iam_role.finding_triage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
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

# ----------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------

resource "aws_lambda_function" "finding_triage" {
  function_name = local.triage_lambda_name
  description   = "Classifies Security Hub findings and checks false positive registry"

  filename         = data.archive_file.finding_triage.output_path
  source_code_hash = data.archive_file.finding_triage.output_base64sha256
  handler          = "finding_triage.lambda_handler"
  runtime          = var.lambda_runtime

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.finding_triage.arn

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      PROJECT_NAME            = var.project_name
      DYNAMODB_TABLE          = var.dynamodb_table_name
      AUTO_REMEDIATE_SEVERITY = var.auto_remediate_severity
      LOG_LEVEL               = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.finding_triage,
    aws_iam_role_policy.finding_triage_logs
  ]

  tags = merge(local.module_tags, {
    Name     = local.triage_lambda_name
    Function = "finding-triage"
  })
}
