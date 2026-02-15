# Budget-Aware Constraints Policy
# Phase 3: IaC Security Gate — Pre-Deployment Prevention
#
# Novel policy — no standard OPA library includes budget enforcement.
# Derived from the project's monthly budget constraint.
# Prevents configurations that would exceed the budget.

package main

import rego.v1

# ──────────────────────────────────────────────────────────────────
# DENY: DynamoDB using PROVISIONED billing mode
# PAY_PER_REQUEST is required to stay within budget.
# Provisioned capacity with even minimal RCU/WCU costs ~$15+/month.
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_dynamodb_table"
	resource.change.actions[_] == "create"

	config := resource.change.after
	config.billing_mode == "PROVISIONED"

	msg := sprintf(
		"CRITICAL: DynamoDB table '%s' uses PROVISIONED billing. Must use PAY_PER_REQUEST to stay within budget. Provisioned capacity starts at ~$15/month even at minimum settings.",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: Lambda function with excessive memory
# 512MB cap prevents accidental cost spikes.
# The project's Lambda functions use 128-256MB.
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_lambda_function"
	resource.change.actions[_] == "create"

	config := resource.change.after
	config.memory_size > 512

	msg := sprintf(
		"CRITICAL: Lambda function '%s' has %dMB memory — maximum allowed is 512MB. The project's functions run well within 128-256MB.",
		[resource.name, config.memory_size],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: Multiple KMS keys (each ~$1/month)
# The project should use a single KMS key shared across services.
# ──────────────────────────────────────────────────────────────────
warn contains msg if {
	kms_keys := [r |
		r := input.resource_changes[_]
		r.type == "aws_kms_key"
		r.change.actions[_] == "create"
	]

	count(kms_keys) > 1

	msg := sprintf(
		"WARNING: %d KMS keys being created. Each KMS key costs ~$1/month. Consider sharing a single key across services to minimize cost.",
		[count(kms_keys)],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: Lambda function with excessive timeout
# 60-second cap prevents runaway executions that consume budget.
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_lambda_function"
	resource.change.actions[_] == "create"

	config := resource.change.after
	config.timeout > 60

	msg := sprintf(
		"CRITICAL: Lambda function '%s' has %ds timeout — maximum allowed is 60s. Long timeouts increase cost risk from runaway executions.",
		[resource.name, config.timeout],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: DynamoDB table without TTL
# Without TTL, tables grow indefinitely, eventually increasing
# storage costs. Remediation audit data has a 90-day TTL in Phase 2.
# ──────────────────────────────────────────────────────────────────
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_dynamodb_table"
	resource.change.actions[_] == "create"

	config := resource.change.after
	not has_ttl(config)

	msg := sprintf(
		"WARNING: DynamoDB table '%s' does not have TTL configured. Without TTL, data grows indefinitely. Phase 2 uses 90-day TTL for audit records.",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# Helper: check for TTL configuration
# ──────────────────────────────────────────────────────────────────
has_ttl(config) if {
	ttl := config.ttl[_]
	ttl.enabled == true
}
