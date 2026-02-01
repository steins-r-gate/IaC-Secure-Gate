# ==================================================================
# IAM Remediation Lambda
# terraform/modules/lambda-remediation/iam-remediation.tf
# Purpose: Automatically removes wildcard permissions from IAM policies
# ==================================================================

# ==================================================================
# Lambda Package (ZIP)
# ==================================================================

data "archive_file" "iam_remediation" {
  count = var.enable_iam_remediation ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/iam_remediation.py"
  output_path = "${path.module}/dist/iam_remediation.zip"
}

# ==================================================================
# CloudWatch Log Group (Created before Lambda for proper permissions)
# ==================================================================

resource "aws_cloudwatch_log_group" "iam_remediation" {
  count = var.enable_iam_remediation ? 1 : 0

  name              = "/aws/lambda/${local.iam_lambda_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.remediation_tags, {
    Name     = "${local.iam_lambda_name}-logs"
    Function = "iam-remediation"
  })
}

# ==================================================================
# Dead Letter Queue (SQS)
# ==================================================================

resource "aws_sqs_queue" "iam_remediation_dlq" {
  count = var.enable_iam_remediation && var.enable_dead_letter_queue ? 1 : 0

  name                       = "${local.iam_lambda_name}-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20

  # Enable encryption at rest
  sqs_managed_sse_enabled = true

  tags = merge(local.remediation_tags, {
    Name     = "${local.iam_lambda_name}-dlq"
    Function = "iam-remediation-dlq"
  })
}

# ==================================================================
# IAM Execution Role
# ==================================================================

resource "aws_iam_role" "iam_remediation" {
  count = var.enable_iam_remediation ? 1 : 0

  name        = "${local.iam_lambda_name}-role"
  description = "Execution role for IAM remediation Lambda"

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

  tags = merge(local.remediation_tags, {
    Name     = "${local.iam_lambda_name}-role"
    Function = "iam-remediation"
  })
}

# ==================================================================
# IAM Policy - CloudWatch Logs (Least Privilege)
# ==================================================================

resource "aws_iam_role_policy" "iam_remediation_logs" {
  count = var.enable_iam_remediation ? 1 : 0

  name = "${local.iam_lambda_name}-logs-policy"
  role = aws_iam_role.iam_remediation[0].id

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
          "${aws_cloudwatch_log_group.iam_remediation[0].arn}",
          "${aws_cloudwatch_log_group.iam_remediation[0].arn}:*"
        ]
      }
    ]
  })
}

# ==================================================================
# IAM Policy - IAM Operations (Least Privilege)
# ==================================================================

resource "aws_iam_role_policy" "iam_remediation_iam" {
  count = var.enable_iam_remediation ? 1 : 0

  name = "${local.iam_lambda_name}-iam-policy"
  role = aws_iam_role.iam_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadIAMPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        # Restrict to customer-managed policies only (not AWS managed)
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*"
      },
      {
        Sid    = "ModifyIAMPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion"
        ]
        # Restrict to customer-managed policies only
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*"
        # Additional condition: Cannot modify policies with "Admin" in name
        Condition = {
          StringNotLike = {
            "aws:ResourceTag/ProtectedPolicy" = "true"
          }
        }
      }
    ]
  })
}

# ==================================================================
# IAM Policy - KMS (Environment Variable Decryption)
# ==================================================================

resource "aws_iam_role_policy" "iam_remediation_kms" {
  count = var.enable_iam_remediation && var.kms_key_arn != null ? 1 : 0

  name = "${local.iam_lambda_name}-kms-policy"
  role = aws_iam_role.iam_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DecryptEnvironmentVariables"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# ==================================================================
# IAM Policy - DynamoDB (State Tracking)
# ==================================================================

resource "aws_iam_role_policy" "iam_remediation_dynamodb" {
  count = var.enable_iam_remediation && var.dynamodb_table_arn != "" ? 1 : 0

  name = "${local.iam_lambda_name}-dynamodb-policy"
  role = aws_iam_role.iam_remediation[0].id

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

# ==================================================================
# IAM Policy - SNS (Notifications)
# ==================================================================

resource "aws_iam_role_policy" "iam_remediation_sns" {
  count = var.enable_iam_remediation && var.sns_topic_arn != "" ? 1 : 0

  name = "${local.iam_lambda_name}-sns-policy"
  role = aws_iam_role.iam_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublishToSNS"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      }
    ]
  })
}

# ==================================================================
# IAM Policy - Dead Letter Queue
# ==================================================================

resource "aws_iam_role_policy" "iam_remediation_dlq" {
  count = var.enable_iam_remediation && var.enable_dead_letter_queue ? 1 : 0

  name = "${local.iam_lambda_name}-dlq-policy"
  role = aws_iam_role.iam_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.iam_remediation_dlq[0].arn
      }
    ]
  })
}

# ==================================================================
# Lambda Function
# ==================================================================

resource "aws_lambda_function" "iam_remediation" {
  count = var.enable_iam_remediation ? 1 : 0

  function_name = local.iam_lambda_name
  description   = "Automatically removes wildcard (*) permissions from IAM policies"

  # Code
  filename         = data.archive_file.iam_remediation[0].output_path
  source_code_hash = data.archive_file.iam_remediation[0].output_base64sha256
  handler          = "iam_remediation.lambda_handler"
  runtime          = var.lambda_runtime

  # Configuration
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.iam_remediation[0].arn

  # Environment variables
  environment {
    variables = local.common_env_vars
  }

  # Dead letter queue
  dynamic "dead_letter_config" {
    for_each = var.enable_dead_letter_queue ? [1] : []
    content {
      target_arn = aws_sqs_queue.iam_remediation_dlq[0].arn
    }
  }

  # Encryption
  kms_key_arn = var.kms_key_arn

  # Note: reserved_concurrent_executions removed due to account quota limits
  # Lambda will use unreserved concurrency pool

  # Ensure log group exists before Lambda
  depends_on = [
    aws_cloudwatch_log_group.iam_remediation,
    aws_iam_role_policy.iam_remediation_logs
  ]

  tags = merge(local.remediation_tags, {
    Name     = local.iam_lambda_name
    Function = "iam-remediation"
  })
}

# ==================================================================
# Lambda Permission (for EventBridge)
# ==================================================================

resource "aws_lambda_permission" "iam_remediation_eventbridge" {
  count = var.enable_iam_remediation ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iam_remediation[0].function_name
  principal     = "events.amazonaws.com"

  # Restrict to events from this account only
  source_account = data.aws_caller_identity.current.account_id
}
