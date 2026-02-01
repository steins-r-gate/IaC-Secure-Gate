# ==================================================================
# Security Group Remediation Lambda
# terraform/modules/lambda-remediation/sg-remediation.tf
# Purpose: Automatically removes overly permissive Security Group rules
# ==================================================================

# ==================================================================
# Lambda Package (ZIP)
# ==================================================================

data "archive_file" "sg_remediation" {
  count = var.enable_sg_remediation ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/${var.lambda_source_path}/sg_remediation.py"
  output_path = "${path.module}/dist/sg_remediation.zip"
}

# ==================================================================
# CloudWatch Log Group
# ==================================================================

resource "aws_cloudwatch_log_group" "sg_remediation" {
  count = var.enable_sg_remediation ? 1 : 0

  name              = "/aws/lambda/${local.sg_lambda_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.remediation_tags, {
    Name     = "${local.sg_lambda_name}-logs"
    Function = "sg-remediation"
  })
}

# ==================================================================
# Dead Letter Queue (SQS)
# ==================================================================

resource "aws_sqs_queue" "sg_remediation_dlq" {
  count = var.enable_sg_remediation && var.enable_dead_letter_queue ? 1 : 0

  name                       = "${local.sg_lambda_name}-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20

  sqs_managed_sse_enabled = true

  tags = merge(local.remediation_tags, {
    Name     = "${local.sg_lambda_name}-dlq"
    Function = "sg-remediation-dlq"
  })
}

# ==================================================================
# IAM Execution Role
# ==================================================================

resource "aws_iam_role" "sg_remediation" {
  count = var.enable_sg_remediation ? 1 : 0

  name        = "${local.sg_lambda_name}-role"
  description = "Execution role for Security Group remediation Lambda"

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
    Name     = "${local.sg_lambda_name}-role"
    Function = "sg-remediation"
  })
}

# ==================================================================
# IAM Policy - CloudWatch Logs
# ==================================================================

resource "aws_iam_role_policy" "sg_remediation_logs" {
  count = var.enable_sg_remediation ? 1 : 0

  name = "${local.sg_lambda_name}-logs-policy"
  role = aws_iam_role.sg_remediation[0].id

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
          "${aws_cloudwatch_log_group.sg_remediation[0].arn}",
          "${aws_cloudwatch_log_group.sg_remediation[0].arn}:*"
        ]
      }
    ]
  })
}

# ==================================================================
# IAM Policy - EC2 Security Group Operations (Least Privilege)
# ==================================================================

resource "aws_iam_role_policy" "sg_remediation_ec2" {
  count = var.enable_sg_remediation ? 1 : 0

  name = "${local.sg_lambda_name}-ec2-policy"
  role = aws_iam_role.sg_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules"
        ]
        Resource = "*"
        # Note: Describe actions don't support resource-level permissions
      },
      {
        Sid    = "ModifySecurityGroupRules"
        Effect = "Allow"
        Action = [
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:security-group/*"
        # Lambda code checks for ProtectedSecurityGroup tag before modification
        Condition = {
          StringNotEquals = {
            "ec2:ResourceTag/ProtectedSecurityGroup" = "true"
          }
        }
      },
      {
        Sid    = "TagSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:security-group/*"
        # Only allow specific remediation tags
        Condition = {
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["RemediatedBy", "RemediatedAt"]
          }
        }
      }
    ]
  })
}

# ==================================================================
# IAM Policy - KMS (Environment Variable Decryption)
# ==================================================================

resource "aws_iam_role_policy" "sg_remediation_kms" {
  count = var.enable_sg_remediation && var.kms_key_arn != null ? 1 : 0

  name = "${local.sg_lambda_name}-kms-policy"
  role = aws_iam_role.sg_remediation[0].id

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

resource "aws_iam_role_policy" "sg_remediation_dynamodb" {
  count = var.enable_sg_remediation && var.dynamodb_table_arn != "" ? 1 : 0

  name = "${local.sg_lambda_name}-dynamodb-policy"
  role = aws_iam_role.sg_remediation[0].id

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

resource "aws_iam_role_policy" "sg_remediation_sns" {
  count = var.enable_sg_remediation && var.sns_topic_arn != "" ? 1 : 0

  name = "${local.sg_lambda_name}-sns-policy"
  role = aws_iam_role.sg_remediation[0].id

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

resource "aws_iam_role_policy" "sg_remediation_dlq" {
  count = var.enable_sg_remediation && var.enable_dead_letter_queue ? 1 : 0

  name = "${local.sg_lambda_name}-dlq-policy"
  role = aws_iam_role.sg_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendToDLQ"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.sg_remediation_dlq[0].arn
      }
    ]
  })
}

# ==================================================================
# Lambda Function
# ==================================================================

resource "aws_lambda_function" "sg_remediation" {
  count = var.enable_sg_remediation ? 1 : 0

  function_name = local.sg_lambda_name
  description   = "Automatically removes overly permissive Security Group ingress rules"

  filename         = data.archive_file.sg_remediation[0].output_path
  source_code_hash = data.archive_file.sg_remediation[0].output_base64sha256
  handler          = "sg_remediation.lambda_handler"
  runtime          = var.lambda_runtime

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  role        = aws_iam_role.sg_remediation[0].arn

  environment {
    variables = local.common_env_vars
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_dead_letter_queue ? [1] : []
    content {
      target_arn = aws_sqs_queue.sg_remediation_dlq[0].arn
    }
  }

  kms_key_arn = var.kms_key_arn

  # Note: reserved_concurrent_executions removed due to account quota limits

  depends_on = [
    aws_cloudwatch_log_group.sg_remediation,
    aws_iam_role_policy.sg_remediation_logs
  ]

  tags = merge(local.remediation_tags, {
    Name     = local.sg_lambda_name
    Function = "sg-remediation"
  })
}

# ==================================================================
# Lambda Permission (for EventBridge)
# ==================================================================

resource "aws_lambda_permission" "sg_remediation_eventbridge" {
  count = var.enable_sg_remediation ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sg_remediation[0].function_name
  principal     = "events.amazonaws.com"

  source_account = data.aws_caller_identity.current.account_id
}
