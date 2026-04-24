# phase3-evidence: Security group open SSH — intentional violation
# Blocked by: Checkov CKV_AWS_24 + OPA policies/opa/sg.rego (deny)
# Mirrors Phase 2 sg_remediation.py is_overly_permissive_rule() at commit time
resource "aws_security_group" "phase3_evidence_sg_ssh" {
  name        = "phase3-evidence-sg-open-ssh"
  description = "Phase 3 evidence test — intentional open SSH violation"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Evidence test: open SSH ingress"
  }
}
