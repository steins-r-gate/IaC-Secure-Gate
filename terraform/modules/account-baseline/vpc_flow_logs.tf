# ==================================================================
# Account Baseline Module - VPC Flow Logs
# terraform/modules/account-baseline/vpc_flow_logs.tf
# Purpose: EC2.6 — Enable VPC flow logging on default VPC
# ==================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==================================================================
# Look Up Default VPC
# ==================================================================

data "aws_vpc" "default" {
  count   = var.enable_default_vpc_flow_logs ? 1 : 0
  default = true
}

# ==================================================================
# CloudWatch Log Group for VPC Flow Logs
# ==================================================================

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0

  name              = "/aws/vpc-flow-logs/${var.project_name}-${var.environment}-default-vpc"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.environment}-vpc-flow-logs"
    Module  = "account-baseline"
    Service = "VPC-Flow-Logs"
  })
}

# ==================================================================
# IAM Role for VPC Flow Logs → CloudWatch
# ==================================================================

data "aws_iam_policy_document" "vpc_flow_logs_assume" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0

  name               = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume[0].json

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
    Module  = "account-baseline"
    Service = "VPC-Flow-Logs"
  })
}

data "aws_iam_policy_document" "vpc_flow_logs_policy" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0

  name   = "${var.project_name}-${var.environment}-vpc-flow-logs-policy"
  role   = aws_iam_role.vpc_flow_logs[0].id
  policy = data.aws_iam_policy_document.vpc_flow_logs_policy[0].json
}

# ==================================================================
# VPC Flow Log
# ==================================================================

resource "aws_flow_log" "default_vpc" {
  count = var.enable_default_vpc_flow_logs ? 1 : 0

  vpc_id          = data.aws_vpc.default[0].id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${var.environment}-default-vpc-flow-log"
    Module  = "account-baseline"
    Service = "VPC-Flow-Logs"
  })
}
