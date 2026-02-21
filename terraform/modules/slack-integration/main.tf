# ==================================================================
# Slack Integration Module - API Gateway
# terraform/modules/slack-integration/main.tf
# Purpose: REST API for receiving Slack interactive callbacks
# ==================================================================

# ----------------------------------------------------------------------
# API Gateway REST API
# ----------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "slack_callback" {
  name        = "${local.name_prefix}-slack-callback"
  description = "Receives Slack interactive message callbacks"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.module_tags, {
    Name = "${local.name_prefix}-slack-callback-api"
  })
}

# /v1 resource
resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.slack_callback.id
  parent_id   = aws_api_gateway_rest_api.slack_callback.root_resource_id
  path_part   = "v1"
}

# /v1/callback resource
resource "aws_api_gateway_resource" "callback" {
  rest_api_id = aws_api_gateway_rest_api.slack_callback.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "callback"
}

# POST /v1/callback method
resource "aws_api_gateway_method" "callback_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_callback.id
  resource_id   = aws_api_gateway_resource.callback.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integration with Lambda
resource "aws_api_gateway_integration" "callback_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.slack_callback.id
  resource_id             = aws_api_gateway_resource.callback.id
  http_method             = aws_api_gateway_method.callback_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_callback.invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "slack_callback" {
  rest_api_id = aws_api_gateway_rest_api.slack_callback.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.v1.id,
      aws_api_gateway_resource.callback.id,
      aws_api_gateway_method.callback_post.id,
      aws_api_gateway_integration.callback_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Stage
resource "aws_api_gateway_stage" "slack_callback" {
  deployment_id = aws_api_gateway_deployment.slack_callback.id
  rest_api_id   = aws_api_gateway_rest_api.slack_callback.id
  stage_name    = var.environment

  tags = merge(local.module_tags, {
    Name = "${local.name_prefix}-slack-callback-stage"
  })
}

# Throttling
resource "aws_api_gateway_method_settings" "slack_callback" {
  rest_api_id = aws_api_gateway_rest_api.slack_callback.id
  stage_name  = aws_api_gateway_stage.slack_callback.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 10
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_callback" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_callback.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.slack_callback.execution_arn}/*/*"
}
