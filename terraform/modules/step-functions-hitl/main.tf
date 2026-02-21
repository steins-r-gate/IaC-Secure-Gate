# ==================================================================
# Step Functions HITL Module - State Machine
# terraform/modules/step-functions-hitl/main.tf
# Purpose: Orchestrates finding triage → approval → remediation
# ==================================================================

# ----------------------------------------------------------------------
# IAM Role for Step Functions
# ----------------------------------------------------------------------

resource "aws_iam_role" "sfn_execution" {
  name        = "${local.state_machine_name}-sfn-role"
  description = "Execution role for HITL orchestrator state machine"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StepFunctionsAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
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
    Name = "${local.state_machine_name}-sfn-role"
  })
}

resource "aws_iam_role_policy" "sfn_invoke_lambdas" {
  name = "${local.state_machine_name}-invoke-lambdas"
  role = aws_iam_role.sfn_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambdaFunctions"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.finding_triage.arn,
          var.slack_notifier_lambda_arn,
          var.iam_remediation_lambda_arn,
          var.s3_remediation_lambda_arn,
          var.sg_remediation_lambda_arn,
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "sfn_logging" {
  name = "${local.state_machine_name}-logging"
  role = aws_iam_role.sfn_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# ----------------------------------------------------------------------
# State Machine Definition
# ----------------------------------------------------------------------

resource "aws_sfn_state_machine" "hitl_orchestrator" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.sfn_execution.arn
  type     = "STANDARD" # Required for waitForTaskToken

  definition = jsonencode({
    Comment = "HITL orchestrator: triage → [auto-fix OR approval] → remediate/skip"
    StartAt = "TriageFinding"
    States = {

      # ── Step 1: Triage the finding ──────────────────────────────
      TriageFinding = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.finding_triage.arn
          Payload = {
            "detail.$"      = "$.detail"
            "source.$"      = "$.source"
            "detail-type.$" = "$.detail-type"
          }
        }
        ResultPath = "$.triage"
        ResultSelector = {
          "decision.$"      = "$.Payload.decision"
          "severity.$"      = "$.Payload.severity"
          "resource_type.$" = "$.Payload.resource_type"
          "resource_arn.$"  = "$.Payload.resource_arn"
          "control_id.$"    = "$.Payload.control_id"
        }
        Next = "RouteByDecision"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "TriageError"
            ResultPath  = "$.error"
          }
        ]
      }

      # ── Step 2: Route based on triage decision ─────────────────
      RouteByDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.triage.decision"
            StringEquals = "AUTO_REMEDIATE"
            Next         = "SelectRemediationLambda"
          },
          {
            Variable     = "$.triage.decision"
            StringEquals = "SKIP_FALSE_POSITIVE"
            Next         = "LogFalsePositive"
          },
          {
            Variable     = "$.triage.decision"
            StringEquals = "REQUEST_APPROVAL"
            Next         = "SendSlackApproval"
          }
        ]
        Default = "SendSlackApproval"
      }

      # ── Auto-remediate path ────────────────────────────────────
      SelectRemediationLambda = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.triage.resource_type"
            StringEquals = "AwsIamPolicy"
            Next         = "RemediateIAM"
          },
          {
            Variable     = "$.triage.resource_type"
            StringEquals = "AwsS3Bucket"
            Next         = "RemediateS3"
          },
          {
            Variable     = "$.triage.resource_type"
            StringEquals = "AwsEc2SecurityGroup"
            Next         = "RemediateSG"
          }
        ]
        Default = "RemediationComplete"
      }

      RemediateIAM = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.iam_remediation_lambda_arn
          Payload = {
            "detail.$"      = "$.detail"
            "source.$"      = "$.source"
            "detail-type.$" = "$.detail-type"
          }
        }
        ResultPath = "$.remediation"
        Next       = "RemediationComplete"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RemediationFailed"
            ResultPath  = "$.error"
          }
        ]
      }

      RemediateS3 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.s3_remediation_lambda_arn
          Payload = {
            "detail.$"      = "$.detail"
            "source.$"      = "$.source"
            "detail-type.$" = "$.detail-type"
          }
        }
        ResultPath = "$.remediation"
        Next       = "RemediationComplete"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RemediationFailed"
            ResultPath  = "$.error"
          }
        ]
      }

      RemediateSG = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.sg_remediation_lambda_arn
          Payload = {
            "detail.$"      = "$.detail"
            "source.$"      = "$.source"
            "detail-type.$" = "$.detail-type"
          }
        }
        ResultPath = "$.remediation"
        Next       = "RemediationComplete"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "RemediationFailed"
            ResultPath  = "$.error"
          }
        ]
      }

      # ── Slack approval path (waitForTaskToken) ─────────────────
      SendSlackApproval = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          FunctionName = var.slack_notifier_lambda_arn
          Payload = {
            "task_token.$" = "$$.Task.Token"
            "finding.$"    = "$.detail"
          }
        }
        ResultPath     = "$.approval"
        TimeoutSeconds = var.approval_timeout_seconds
        Next           = "RouteByApproval"
        Catch = [
          {
            ErrorEquals = ["States.Timeout"]
            Next        = "TimeoutAutoRemediate"
            ResultPath  = "$.error"
          },
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ApprovalError"
            ResultPath  = "$.error"
          }
        ]
      }

      RouteByApproval = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.approval.decision"
            StringEquals = "APPROVED"
            Next         = "SelectRemediationLambda"
          },
          {
            Variable     = "$.approval.decision"
            StringEquals = "FALSE_POSITIVE"
            Next         = "LogFalsePositive"
          }
        ]
        Default = "SelectRemediationLambda"
      }

      # ── Timeout: auto-remediate with notification ──────────────
      TimeoutAutoRemediate = {
        Type    = "Pass"
        Comment = "Approval timed out — proceeding with auto-remediation"
        Next    = "SelectRemediationLambda"
      }

      # ── False positive: log and succeed ────────────────────────
      LogFalsePositive = {
        Type    = "Pass"
        Comment = "Finding marked as false positive — logged to registry"
        Result = {
          "status" = "FALSE_POSITIVE_LOGGED"
        }
        ResultPath = "$.result"
        End        = true
      }

      # ── Terminal states ────────────────────────────────────────
      RemediationComplete = {
        Type    = "Succeed"
        Comment = "Remediation completed successfully"
      }

      RemediationFailed = {
        Type  = "Fail"
        Error = "RemediationFailed"
        Cause = "Remediation Lambda returned an error"
      }

      TriageError = {
        Type  = "Fail"
        Error = "TriageError"
        Cause = "Finding triage Lambda returned an error"
      }

      ApprovalError = {
        Type  = "Fail"
        Error = "ApprovalError"
        Cause = "Slack approval workflow encountered an error"
      }
    }
  })

  tags = merge(local.module_tags, {
    Name = local.state_machine_name
  })
}
