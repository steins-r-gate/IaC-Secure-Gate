# ==================================================================
# S3 Remediation Lambda
# terraform/modules/lambda-remediation/s3-remediation.tf
# Purpose: Automatically secures S3 buckets (public access, encryption, versioning)
# ==================================================================

# ==================================================================
# Lambda Package (ZIP)
# ==================================================================

data "archive_file" "s3_remediation" {
  count = var.enable_s3_remediation ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/s3_remediation.py"
  output_path = "${path.module}/dist/s3_remediation.zip"
}

# ==================================================================
# CloudWatch Log Group
# ==================================================================

resource "aws_cloudwatch_log_group" "s3_remediation" {
  count = var.enable_s3_remediation ? 1 : 0

  name              = "/aws/lambda/${local.s3_lambda_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.remediation_tags, {
    Name     = "${local.s3_lambda_name}-logs"
    Function = "s3-remediation"
  })
}

# ==================================================================
# Dead Letter Queue (SQS)
# ==================================================================

resource "aws_sqs_queue" "s3_remediation_dlq" {
  count = var.enable_s3_remediation && var.enable_dead_letter_queue ? 1 : 0

  name                       = "${local.s3_lambda_name}-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20

  sqs_managed_sse_enabled = true

  tags = merge(local.remediation_tags, {
    Name     = "${local.s3_lambda_name}-dlq"
    Function = "s3-remediation-dlq"
  })
}

# ==================================================================
# IAM Execution Role
# ==================================================================

resource "aws_iam_role" "s3_remediation" {
  count = var.enable_s3_remediation ? 1 : 0

  name        = "${local.s3_lambda_name}-role"
  description = "Execution role for S3 remediation Lambda"

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
    Name     = "${local.s3_lambda_name}-role"
    Function = "s3-remediation"
  })
}

# ==================================================================
# IAM Policy - CloudWatch Logs
# ==================================================================

resource "aws_iam_role_policy" "s3_remediation_logs" {
  count = var.enable_s3_remediation ? 1 : 0

  name = "${local.s3_lambda_name}-logs-policy"
  role = aws_iam_role.s3_remediation[0].id

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
          "${aws_cloudwatch_log_group.s3_remediation[0].arn}",
          "${aws_cloudwatch_log_group.s3_remediation[0].arn}:*"
        ]
      }
    ]
  })
}

# ==================================================================
# IAM Policy - S3 Operations (Least Privilege)
# ==================================================================

resource "aws_iam_role_policy" "s3_remediation_s3" {
  count = var.enable_s3_remediation ? 1 : 0

  name = "${local.s3_lambda_name}-s3-policy"
  role = aws_iam_role.s3_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadBucketConfiguration"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetBucketTagging"
        ]
        Resource = "arn:aws:s3:::*"
        # Note: S3 bucket-level permissions cannot use account conditions
        # Security is enforced by the Lambda's validation logic
      },
      {
        Sid    = "ModifyBucketSecurity"
        Effect = "Allow"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketEncryption",
          "s3:PutBucketVersioning"
        ]
        Resource = "arn:aws:s3:::*"
        # Lambda code checks for ProtectedBucket tag before modification
      }
    ]
  })
}

# ==================================================================
# IAM Policy - KMS (Environment Variable Decryption)
# ==================================================================

resource "aws_iam_role_policy" "s3_remediation_kms" {
  count = var.enable_s3_remediation && var.kms_key_arn != null ? 1 : 0

  name = "${local.s3_lambda_name}-kms-policy"
  role = aws_iam_role.s3_remediation[0].id

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

resource "aws_iam_role_policy" "s3_remediation_dynamodb" {
  count = var.enable_s3_remediation && var.enable_dynamodb_logging ? 1 : 0

  name = "${local.s3_lambda_name}-dynamodb-policy"
  role = aws_iam_role.s3_remediation[0].id

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

resource "aws_iam_role_policy" "s3_remediation_sns" {
  count = var.enable_s3_remediation && var.sns_topic_arn != "" ? 1 : 0

  name = "${local.s3_lambda_name}-sns-policy"
  role = aws_iam_role.s3_remediation[0].id

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

resource "aws_iam_role_policy" "s3_remediation_dlq" {
  count = var.enable_s3_remediation && var.enable_dead_letter_queue ? 1 : 0

  name = "${local.s3_lambda_name}-dlq-policy"
  role = aws_iam_role.s3_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.s3_remediation_dlq[0].arn
      }
    ]
  })
}

# ==================================================================
# Lambda Function
# ==================================================================

resource "aws_lambda_function" "s3_remediation" {
  count = var.enable_s3_remediation ? 1 : 0

  function_name = local.s3_lambda_name
  description   = "Automatically secures S3 buckets (blocks public access, enables encryption and versioning)"

  filename         = data.archive_file.s3_remediation[0].output_path
  source_code_hash = data.archive_file.s3_remediation[0].output_base64sha256
  handler          = "s3_remediation.lambda_handler"
  runtime          = var.lambda_runtime

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.s3_remediation[0].arn

  environment {
    variables = local.common_env_vars
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_dead_letter_queue ? [1] : []
    content {
      target_arn = aws_sqs_queue.s3_remediation_dlq[0].arn
    }
  }

  kms_key_arn = var.kms_key_arn

  # Note: reserved_concurrent_executions removed due to account quota limits

  depends_on = [
    aws_cloudwatch_log_group.s3_remediation,
    aws_iam_role_policy.s3_remediation_logs
  ]

  tags = merge(local.remediation_tags, {
    Name     = local.s3_lambda_name
    Function = "s3-remediation"
  })
}

# ==================================================================
# Lambda Permission (for EventBridge)
# ==================================================================

resource "aws_lambda_permission" "s3_remediation_eventbridge" {
  count = var.enable_s3_remediation ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_remediation[0].function_name
  principal     = "events.amazonaws.com"

  source_account = data.aws_caller_identity.current.account_id
}
