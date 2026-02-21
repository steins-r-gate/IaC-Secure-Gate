# ==================================================================
# Slack Integration Module - SSM Parameters
# terraform/modules/slack-integration/ssm.tf
# Purpose: Store Slack credentials securely in SSM Parameter Store
# ==================================================================

resource "aws_ssm_parameter" "slack_bot_token" {
  name        = "/${var.project_name}/${var.environment}/slack/bot-token"
  description = "Slack Bot User OAuth Token"
  type        = "SecureString"
  value       = var.slack_bot_token

  tags = merge(local.module_tags, {
    Name = "${local.name_prefix}-slack-bot-token"
  })
}

resource "aws_ssm_parameter" "slack_signing_secret" {
  name        = "/${var.project_name}/${var.environment}/slack/signing-secret"
  description = "Slack app signing secret for HMAC verification"
  type        = "SecureString"
  value       = var.slack_signing_secret

  tags = merge(local.module_tags, {
    Name = "${local.name_prefix}-slack-signing-secret"
  })
}
