# Cross-Service Encryption Policy
# Phase 3: IaC Security Gate — Pre-Deployment Prevention
#
# Enforces encryption across services used by IaC-Secure-Gate.
# Extends Phase 2 S3 encryption checks to DynamoDB, SQS, and CloudWatch Logs.
# Security Hub Controls: DynamoDB.1, SQS.1

package main

# ──────────────────────────────────────────────────────────────────
# DENY: DynamoDB table without encryption specification
# The project uses DynamoDB for remediation audit trails — data at
# rest must be encrypted.
# ──────────────────────────────────────────────────────────────────
deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_dynamodb_table"
	resource.change.actions[_] == "create"

	not has_dynamodb_sse(resource)

	msg := sprintf(
		"CRITICAL: DynamoDB table '%s' does not have server-side encryption configured. All tables storing remediation data must be encrypted. [Security Hub: DynamoDB.1]",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: SQS queue without encryption
# ──────────────────────────────────────────────────────────────────
deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_sqs_queue"
	resource.change.actions[_] == "create"

	config := resource.change.after
	not config.sqs_managed_sse_enabled
	not config.kms_master_key_id

	msg := sprintf(
		"CRITICAL: SQS queue '%s' does not have encryption enabled. Enable SSE-SQS or KMS encryption. [Security Hub: SQS.1]",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: CloudWatch Log Group without KMS encryption
# Warning level — CloudWatch encrypts by default with service keys,
# but KMS provides customer-managed control.
# ──────────────────────────────────────────────────────────────────
warn[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_cloudwatch_log_group"
	resource.change.actions[_] == "create"

	config := resource.change.after
	not config.kms_key_id

	msg := sprintf(
		"WARNING: CloudWatch Log Group '%s' does not use KMS encryption. Consider using a customer-managed KMS key for sensitive log data.",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: SNS topic without encryption
# The project uses SNS for remediation notifications.
# ──────────────────────────────────────────────────────────────────
deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_sns_topic"
	resource.change.actions[_] == "create"

	config := resource.change.after
	not config.kms_master_key_id

	msg := sprintf(
		"CRITICAL: SNS topic '%s' does not have KMS encryption configured. Remediation notifications may contain sensitive resource information.",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# Helper: check DynamoDB SSE configuration
# ──────────────────────────────────────────────────────────────────
has_dynamodb_sse(resource) {
	sse := resource.change.after.server_side_encryption[_]
	sse.enabled == true
}
