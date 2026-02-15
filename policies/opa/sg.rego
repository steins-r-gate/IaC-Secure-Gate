# Security Group Open Access Policy
# Phase 3: IaC Security Gate — Pre-Deployment Prevention
#
# Mirrors: lambda/src/sg_remediation.py → is_overly_permissive_rule() (Lines 168-233)
# Security Hub Controls: EC2.2, EC2.18, EC2.19, EC2.21
#
# Phase 2 remediates overly permissive security group rules at runtime.
# This policy blocks them at commit time — same ports, same logic, earlier enforcement.

package main

import rego.v1

# ──────────────────────────────────────────────────────────────────
# Dangerous ports — identical to Phase 2 Lambda
# Source: lambda/src/sg_remediation.py, Lines 214-226
# ──────────────────────────────────────────────────────────────────
dangerous_ports := {
	22,    # SSH — Remote shell access
	23,    # Telnet — Unencrypted remote access
	1433,  # MSSQL — Database exposure
	3306,  # MySQL — Database exposure
	3389,  # RDP — Windows remote desktop
	5432,  # PostgreSQL — Database exposure
	5601,  # Kibana — Dashboard exposure
	6379,  # Redis — Cache/store exposure
	9200,  # Elasticsearch — Search engine exposure
	11211, # Memcached — Cache exposure
	27017, # MongoDB — NoSQL database exposure
}

# ──────────────────────────────────────────────────────────────────
# DENY: Security group ingress rule with dangerous port open to 0.0.0.0/0
# Mirrors: sg_remediation.py → is_overly_permissive_rule() check for
#          dangerous_ports with 0.0.0.0/0 source (Lines 213-232)
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	rule := resource.change.after.ingress[_]

	# Check for public source
	cidr := rule.cidr_blocks[_]
	cidr == "0.0.0.0/0"

	# Check if port range includes a dangerous port
	port := dangerous_ports[_]
	rule.from_port <= port
	port <= rule.to_port

	msg := sprintf(
		"CRITICAL: Security group '%s' allows ingress on port %d from 0.0.0.0/0. Phase 2 would remove this rule at runtime. [Mirrors: sg_remediation.py L214-226, Security Hub: EC2.18]",
		[resource.name, port],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: Security group ingress rule with dangerous port open to ::/0 (IPv6)
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	rule := resource.change.after.ingress[_]

	cidr := rule.ipv6_cidr_blocks[_]
	cidr == "::/0"

	port := dangerous_ports[_]
	rule.from_port <= port
	port <= rule.to_port

	msg := sprintf(
		"CRITICAL: Security group '%s' allows ingress on port %d from ::/0 (IPv6). Phase 2 would remove this rule at runtime. [Mirrors: sg_remediation.py L214-226, Security Hub: EC2.19]",
		[resource.name, port],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: Security group with all-traffic protocol (-1) open to public
# Mirrors: sg_remediation.py L194 — protocol "-1" is always dangerous
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	rule := resource.change.after.ingress[_]

	cidr := rule.cidr_blocks[_]
	cidr == "0.0.0.0/0"

	rule.protocol == "-1"

	msg := sprintf(
		"CRITICAL: Security group '%s' allows ALL traffic from 0.0.0.0/0. This is the most permissive rule possible. [Mirrors: sg_remediation.py L194, Security Hub: EC2.2]",
		[resource.name],
	)
}

deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	rule := resource.change.after.ingress[_]

	cidr := rule.ipv6_cidr_blocks[_]
	cidr == "::/0"

	rule.protocol == "-1"

	msg := sprintf(
		"CRITICAL: Security group '%s' allows ALL traffic from ::/0 (IPv6). This is the most permissive rule possible. [Mirrors: sg_remediation.py L194, Security Hub: EC2.2]",
		[resource.name],
	)
}

# ──────────────────────────────────────────────────────────────────
# DENY: Standalone security group rules (aws_security_group_rule)
# Same checks but for separate ingress rule resources
# ──────────────────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group_rule"
	resource.change.after.type == "ingress"

	cidr := resource.change.after.cidr_blocks[_]
	cidr == "0.0.0.0/0"

	port := dangerous_ports[_]
	resource.change.after.from_port <= port
	port <= resource.change.after.to_port

	msg := sprintf(
		"CRITICAL: Security group rule '%s' allows ingress on port %d from 0.0.0.0/0. [Mirrors: sg_remediation.py L214-226]",
		[resource.name, port],
	)
}

# ──────────────────────────────────────────────────────────────────
# WARN: Wide port range open to public (>100 ports)
# Mirrors: sg_remediation.py L210 — port range too wide
# ──────────────────────────────────────────────────────────────────
warn contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	rule := resource.change.after.ingress[_]

	cidr := rule.cidr_blocks[_]
	cidr == "0.0.0.0/0"

	port_range := rule.to_port - rule.from_port
	port_range > 100

	rule.protocol != "-1"

	msg := sprintf(
		"WARNING: Security group '%s' has a wide port range (%d-%d, %d ports) open to 0.0.0.0/0. [Mirrors: sg_remediation.py L210]",
		[resource.name, rule.from_port, rule.to_port, port_range],
	)
}
