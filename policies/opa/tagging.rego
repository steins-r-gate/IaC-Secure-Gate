# Required Resource Tags Policy
# Phase 3: IaC Security Gate — Pre-Deployment Prevention
#
# Enforces mandatory tags on all taggable AWS resources.
# Tags enable cost tracking, environment identification, and resource ownership.

package main

import rego.v1

# ──────────────────────────────────────────────────────────────────
# Required tags for all taggable resources
# ──────────────────────────────────────────────────────────────────
required_tags := {"Project", "Environment", "ManagedBy"}

# ──────────────────────────────────────────────────────────────────
# Resource types that must have tags
# These are the types used in the IaC-Secure-Gate project
# ──────────────────────────────────────────────────────────────────
taggable_resources := {
	"aws_s3_bucket",
	"aws_dynamodb_table",
	"aws_lambda_function",
	"aws_sns_topic",
	"aws_sqs_queue",
	"aws_kms_key",
	"aws_cloudwatch_log_group",
	"aws_iam_role",
	"aws_security_group",
}

# ──────────────────────────────────────────────────────────────────
# DENY: Taggable resource missing required tags
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type in taggable_resources
	resource.change.actions[_] == "create"

	tags := object.get(resource.change.after, "tags", {})
	tag := required_tags[_]
	not tags[tag]

	msg := sprintf(
		"CRITICAL: Resource '%s' (type: %s) is missing required tag '%s'. All resources must have tags: %s.",
		[resource.name, resource.type, tag, concat(", ", required_tags)],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: ManagedBy tag must be "terraform"
# Ensures all resources declare Terraform as the management tool,
# preventing configuration drift from manual changes.
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type in taggable_resources
	resource.change.actions[_] == "create"

	tags := object.get(resource.change.after, "tags", {})
	tags.ManagedBy
	tags.ManagedBy != "terraform"

	msg := sprintf(
		"CRITICAL: Resource '%s' has ManagedBy='%s' — must be 'terraform'. This ensures infrastructure is managed through IaC only.",
		[resource.name, tags.ManagedBy],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: Environment tag has unexpected value
# ──────────────────────────────────────────────────────────────────
valid_environments := {"dev", "staging", "prod"}

warn contains msg if {
	resource := input.resource_changes[_]
	resource.type in taggable_resources
	resource.change.actions[_] == "create"

	tags := object.get(resource.change.after, "tags", {})
	tags.Environment
	not tags.Environment in valid_environments

	msg := sprintf(
		"WARNING: Resource '%s' has Environment='%s' — expected one of: %s.",
		[resource.name, tags.Environment, concat(", ", valid_environments)],
	)
}
