# ==================================================================
# Remediation Tracking Module - DynamoDB Table
# terraform/modules/remediation-tracking/dynamodb.tf
#
# Purpose: Store remediation history for audit trail and analytics
# Schema:
#   - Partition Key: violation_type (IAM, S3, SecurityGroup)
#   - Sort Key: timestamp (ISO 8601 format)
#   - GSI1: resource_arn-index (query by affected resource)
#   - GSI2: status-index (query by remediation status)
# ==================================================================

# ----------------------------------------------------------------------
# DynamoDB Table
# ----------------------------------------------------------------------

resource "aws_dynamodb_table" "remediation_history" {
  name         = local.table_name
  billing_mode = var.billing_mode

  # Only set capacity if using PROVISIONED billing
  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  # Primary key design for efficient time-series queries
  # Partition by violation type allows parallel processing
  hash_key  = "violation_type"
  range_key = "timestamp"

  # Attribute definitions for keys and indexes
  attribute {
    name = "violation_type"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "resource_arn"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # Approval ID attribute (for HITL CI gate lookups)
  dynamic "attribute" {
    for_each = var.enable_approval_index ? [1] : []
    content {
      name = "approval_id"
      type = "S"
    }
  }

  # GSI1: Query by resource ARN (find all remediations for a specific resource)
  dynamic "global_secondary_index" {
    for_each = var.enable_resource_index ? [1] : []
    content {
      name            = "resource-arn-index"
      hash_key        = "resource_arn"
      range_key       = "timestamp"
      projection_type = "ALL"

      # For PAY_PER_REQUEST, capacity is managed automatically
      read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
      write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
    }
  }

  # GSI2: Query by status (find all failed remediations)
  dynamic "global_secondary_index" {
    for_each = var.enable_status_index ? [1] : []
    content {
      name            = "status-index"
      hash_key        = "status"
      range_key       = "timestamp"
      projection_type = "ALL"

      read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
      write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
    }
  }

  # GSI3: Query by approval ID (for CI gate polling)
  dynamic "global_secondary_index" {
    for_each = var.enable_approval_index ? [1] : []
    content {
      name            = "approval-id-index"
      hash_key        = "approval_id"
      projection_type = "ALL"

      read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
      write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
    }
  }

  # Enable DynamoDB Streams for Phase 3 (real-time processing)
  stream_enabled   = var.enable_dynamodb_stream
  stream_view_type = var.enable_dynamodb_stream ? var.stream_view_type : null

  # TTL for automatic cleanup of old records
  ttl {
    enabled        = var.ttl_enabled
    attribute_name = var.ttl_attribute_name
  }

  # Point-in-Time Recovery for data protection
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn # null = AWS managed key (free)
  }

  # Deletion protection (enabled in prod)
  deletion_protection_enabled = var.environment == "prod" ? true : false

  tags = merge(local.module_tags, {
    Name        = local.table_name
    Description = "Stores remediation history for audit and analytics"
  })

  lifecycle {
    # Prevent accidental deletion of table with data
    prevent_destroy = false # Set to true in prod
  }
}

# ----------------------------------------------------------------------
# IAM Policy for Lambda Access to DynamoDB
# This policy should be attached to Lambda execution roles
# ----------------------------------------------------------------------

resource "aws_iam_policy" "dynamodb_access" {
  name        = "${local.name_prefix}-dynamodb-access"
  description = "Allows Lambda functions to read/write to remediation history table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.remediation_history.arn,
          "${aws_dynamodb_table.remediation_history.arn}/index/*"
        ]
      },
      {
        Sid    = "DynamoDBDescribe"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:DescribeTimeToLive"
        ]
        Resource = aws_dynamodb_table.remediation_history.arn
      }
    ]
  })

  tags = local.module_tags
}

# ----------------------------------------------------------------------
# CloudWatch Alarms for DynamoDB Monitoring
# ----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "throttled_requests" {
  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB table experiencing throttled requests"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.remediation_history.name
  }

  tags = local.module_tags
}

resource "aws_cloudwatch_metric_alarm" "system_errors" {
  alarm_name          = "${local.name_prefix}-dynamodb-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB table experiencing system errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.remediation_history.name
  }

  tags = local.module_tags
}
