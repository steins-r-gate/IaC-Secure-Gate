# S3 Public Access & Encryption Policy
# Phase 3: IaC Security Gate — Pre-Deployment Prevention
#
# Mirrors: lambda/src/s3_remediation.py → block_public_access() (Lines 230-255),
#          enable_encryption() (Lines 258-287)
# Security Hub Controls: S3.1, S3.2, S3.3, S3.4, S3.5, S3.8, S3.19
#
# Phase 2 remediates public S3 buckets and missing encryption at runtime.
# This policy blocks them at commit time — same checks, earlier enforcement point.

package main

import rego.v1

# ──────────────────────────────────────────────────────────────────
# DENY: S3 bucket missing public access block
# Mirrors: s3_remediation.py → block_public_access() (Lines 238-243)
# All four settings must be true — identical to Phase 2 Lambda
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	config := resource.change.after

	not config.block_public_acls

	msg := sprintf(
		"CRITICAL: S3 public access block '%s' has block_public_acls disabled. Phase 2 would enforce BlockPublicAcls=True at runtime. [Mirrors: s3_remediation.py L238-243]",
		[resource.name],
	)
}

deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	config := resource.change.after

	not config.ignore_public_acls

	msg := sprintf(
		"CRITICAL: S3 public access block '%s' has ignore_public_acls disabled. Phase 2 would enforce IgnorePublicAcls=True at runtime. [Mirrors: s3_remediation.py L238-243]",
		[resource.name],
	)
}

deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	config := resource.change.after

	not config.block_public_policy

	msg := sprintf(
		"CRITICAL: S3 public access block '%s' has block_public_policy disabled. Phase 2 would enforce BlockPublicPolicy=True at runtime. [Mirrors: s3_remediation.py L238-243]",
		[resource.name],
	)
}

deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	config := resource.change.after

	not config.restrict_public_buckets

	msg := sprintf(
		"CRITICAL: S3 public access block '%s' has restrict_public_buckets disabled. Phase 2 would enforce RestrictPublicBuckets=True at runtime. [Mirrors: s3_remediation.py L238-243]",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: S3 bucket without a public access block resource
# Every aws_s3_bucket should have a corresponding public access block
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket"
	resource.change.actions[_] == "create"

	bucket_name := resource.name

	not has_public_access_block(bucket_name)

	msg := sprintf(
		"CRITICAL: S3 bucket '%s' has no aws_s3_bucket_public_access_block resource. All buckets must have public access blocked. [Security Hub: S3.1, S3.2, S3.3]",
		[bucket_name],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: S3 bucket without server-side encryption
# Mirrors: s3_remediation.py → enable_encryption() (Lines 258-287)
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket"
	resource.change.actions[_] == "create"

	bucket_name := resource.name

	not has_encryption_config(bucket_name)

	msg := sprintf(
		"CRITICAL: S3 bucket '%s' has no aws_s3_bucket_server_side_encryption_configuration. Phase 2 would enable SSE-S3 encryption at runtime. [Mirrors: s3_remediation.py L258-287, Security Hub: S3.4]",
		[bucket_name],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: S3 bucket without versioning
# Mirrors: s3_remediation.py → enable_versioning() (Lines 290-309)
# ──────────────────────────────────────────────────────────────────
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket"
	resource.change.actions[_] == "create"

	bucket_name := resource.name

	not has_versioning(bucket_name)

	msg := sprintf(
		"WARNING: S3 bucket '%s' has no versioning configuration. Phase 2 would enable versioning at runtime. [Mirrors: s3_remediation.py L290-309, Security Hub: S3.19]",
		[bucket_name],
	)
}

# ──────────────────────────────────────────────────────────────────
# Helpers: check for companion resources
# ──────────────────────────────────────────────────────────────────
has_public_access_block(bucket_name) if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	contains(resource.address, bucket_name)
}

has_encryption_config(bucket_name) if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_server_side_encryption_configuration"
	contains(resource.address, bucket_name)
}

has_versioning(bucket_name) if {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_versioning"
	contains(resource.address, bucket_name)
}
