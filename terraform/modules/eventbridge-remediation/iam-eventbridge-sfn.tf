# ==================================================================
# EventBridge → Step Functions IAM Role
# terraform/modules/eventbridge-remediation/iam-eventbridge-sfn.tf
# Purpose: Allows EventBridge to start Step Functions executions
# ==================================================================

resource "aws_iam_role" "eventbridge_sfn" {
  count = var.enable_hitl ? 1 : 0

  name        = "${local.name_prefix}-eventbridge-sfn-role"
  description = "Allows EventBridge to start HITL Step Functions executions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
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

  tags = merge(local.eventbridge_tags, {
    Name = "${local.name_prefix}-eventbridge-sfn-role"
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn_start" {
  count = var.enable_hitl ? 1 : 0

  name = "${local.name_prefix}-eventbridge-sfn-start"
  role = aws_iam_role.eventbridge_sfn[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartSFNExecution"
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = var.step_functions_arn
      }
    ]
  })
}
