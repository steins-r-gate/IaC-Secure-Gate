# IAM Wildcard Permission Policy
# Phase 3: IaC Security Gate — Pre-Deployment Prevention
#
# Mirrors: lambda/src/iam_remediation.py → is_dangerous_wildcard_action() (Lines 123-151)
# Security Hub Controls: IAM.1, IAM.21
#
# Phase 2 remediates wildcard IAM permissions at runtime.
# This policy blocks them at commit time — same patterns, earlier enforcement point.

package main

import future.keywords.in

# ──────────────────────────────────────────────────────────────────
# Dangerous action patterns — identical to Phase 2 Lambda
# Source: lambda/src/iam_remediation.py, Lines 141-145
# ──────────────────────────────────────────────────────────────────
dangerous_actions := {
	"*",     # Full admin — all services, all actions
	"iam:*", # Full IAM admin — can escalate privileges
	"*:*",   # Any service admin — equivalent to "*"
}

# ──────────────────────────────────────────────────────────────────
# DENY: IAM policies with wildcard actions on wildcard resources
# ──────────────────────────────────────────────────────────────────
deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_policy"
	resource.change.after.policy != null

	policy := json.unmarshal(resource.change.after.policy)
	statement := policy.Statement[_]

	statement.Effect == "Allow"

	actions := as_array(statement.Action)
	action := actions[_]
	action in dangerous_actions

	resources := as_array(statement.Resource)
	"*" in resources

	msg := sprintf(
		"CRITICAL: IAM policy '%s' contains dangerous wildcard action '%s' on Resource '*'. Phase 2 would remediate this at runtime — blocking at commit time instead. [Mirrors: iam_remediation.py L141-145]",
		[resource.name, action],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: IAM role assume_role_policy with wildcard principals
# ──────────────────────────────────────────────────────────────────
deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_role"
	resource.change.after.assume_role_policy != null

	policy := json.unmarshal(resource.change.after.assume_role_policy)
	statement := policy.Statement[_]

	statement.Effect == "Allow"

	principals := as_array(object.get(statement, "Principal", []))
	principal := principals[_]
	principal == "*"

	msg := sprintf(
		"CRITICAL: IAM role '%s' allows assumption by wildcard principal '*'. This permits any AWS account to assume this role. [Security Hub: IAM.1]",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: IAM policies with wildcard actions on specific resources
# Less severe than wildcard resource, but still risky
# ──────────────────────────────────────────────────────────────────
warn[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_policy"
	resource.change.after.policy != null

	policy := json.unmarshal(resource.change.after.policy)
	statement := policy.Statement[_]

	statement.Effect == "Allow"

	actions := as_array(statement.Action)
	action := actions[_]
	action in dangerous_actions

	resources := as_array(statement.Resource)
	not "*" in resources

	msg := sprintf(
		"WARNING: IAM policy '%s' uses dangerous wildcard action '%s'. Even with scoped resources, wildcard actions grant excessive permissions. [Security Hub: IAM.21]",
		[resource.name, action],
	)
}

# ──────────────────────────────────────────────────────────────────
# Helper: normalize value to array
# ──────────────────────────────────────────────────────────────────
as_array(value) = [value] {
	is_string(value)
}

as_array(value) = value {
	is_array(value)
}
