# ==================================================================
# CIS Alarms Module - CloudWatch Metric Filters & Alarms
# terraform/modules/cis-alarms/main.tf
# Purpose: CIS AWS Foundations Benchmark CloudWatch alarms
#          CloudWatch.1,4,5,6,7,10,11,12,13,14
# ==================================================================

locals {
  cis_alarms = {
    root_usage = {
      description    = "CIS CloudWatch.1 — Root account usage detected"
      filter_pattern = "{($.userIdentity.type=\"Root\") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType !=\"AwsServiceEvent\")}"
    }
    iam_policy_changes = {
      description    = "CIS CloudWatch.4 — IAM policy changes detected"
      filter_pattern = "{($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=CreatePolicyVersion) || ($.eventName=DeletePolicyVersion) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy)}"
    }
    cloudtrail_config_changes = {
      description    = "CIS CloudWatch.5 — CloudTrail configuration changes detected"
      filter_pattern = "{($.eventName=CreateTrail) || ($.eventName=UpdateTrail) || ($.eventName=DeleteTrail) || ($.eventName=StartLogging) || ($.eventName=StopLogging)}"
    }
    console_auth_failures = {
      description    = "CIS CloudWatch.6 — Console authentication failures detected"
      filter_pattern = "{($.eventName=ConsoleLogin) && ($.errorMessage=\"Failed authentication\")}"
    }
    cmk_disable_delete = {
      description    = "CIS CloudWatch.7 — Disabling or scheduled deletion of CMKs detected"
      filter_pattern = "{($.eventSource=kms.amazonaws.com) && (($.eventName=DisableKey) || ($.eventName=ScheduleKeyDeletion))}"
    }
    security_group_changes = {
      description    = "CIS CloudWatch.10 — Security group changes detected"
      filter_pattern = "{($.eventName=AuthorizeSecurityGroupIngress) || ($.eventName=AuthorizeSecurityGroupEgress) || ($.eventName=RevokeSecurityGroupIngress) || ($.eventName=RevokeSecurityGroupEgress) || ($.eventName=CreateSecurityGroup) || ($.eventName=DeleteSecurityGroup)}"
    }
    nacl_changes = {
      description    = "CIS CloudWatch.11 — Network ACL changes detected"
      filter_pattern = "{($.eventName=CreateNetworkAcl) || ($.eventName=CreateNetworkAclEntry) || ($.eventName=DeleteNetworkAcl) || ($.eventName=DeleteNetworkAclEntry) || ($.eventName=ReplaceNetworkAclEntry) || ($.eventName=ReplaceNetworkAclAssociation)}"
    }
    network_gateway_changes = {
      description    = "CIS CloudWatch.12 — Network gateway changes detected"
      filter_pattern = "{($.eventName=CreateCustomerGateway) || ($.eventName=DeleteCustomerGateway) || ($.eventName=AttachInternetGateway) || ($.eventName=CreateInternetGateway) || ($.eventName=DeleteInternetGateway) || ($.eventName=DetachInternetGateway)}"
    }
    route_table_changes = {
      description    = "CIS CloudWatch.13 — Route table changes detected"
      filter_pattern = "{($.eventName=CreateRoute) || ($.eventName=CreateRouteTable) || ($.eventName=ReplaceRoute) || ($.eventName=ReplaceRouteTableAssociation) || ($.eventName=DeleteRouteTable) || ($.eventName=DeleteRoute) || ($.eventName=DisassociateRouteTable)}"
    }
    vpc_changes = {
      description    = "CIS CloudWatch.14 — VPC changes detected"
      filter_pattern = "{($.eventName=CreateVpc) || ($.eventName=DeleteVpc) || ($.eventName=ModifyVpcAttribute) || ($.eventName=AcceptVpcPeeringConnection) || ($.eventName=CreateVpcPeeringConnection) || ($.eventName=DeleteVpcPeeringConnection) || ($.eventName=RejectVpcPeeringConnection) || ($.eventName=AttachClassicLinkVpc) || ($.eventName=DetachClassicLinkVpc) || ($.eventName=DisableVpcClassicLink) || ($.eventName=EnableVpcClassicLink)}"
    }
  }

  cis_alarms_tags = merge(var.common_tags, {
    Module  = "cis-alarms"
    Service = "CloudWatch"
  })
}

# ==================================================================
# Metric Filters — One per CIS alarm definition
# ==================================================================

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each = var.enable_cis_alarms ? local.cis_alarms : {}

  name           = "${var.project_name}-${var.environment}-cis-${each.key}"
  log_group_name = var.cloudtrail_log_group_name
  pattern        = each.value.filter_pattern

  metric_transformation {
    name          = "CIS-${each.key}"
    namespace     = var.metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# ==================================================================
# CloudWatch Alarms — One per metric filter
# ==================================================================

resource "aws_cloudwatch_metric_alarm" "cis" {
  for_each = var.enable_cis_alarms ? local.cis_alarms : {}

  alarm_name          = "${var.project_name}-${var.environment}-cis-${each.key}"
  alarm_description   = each.value.description
  metric_name         = "CIS-${each.key}"
  namespace           = var.metric_namespace
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arns

  tags = merge(local.cis_alarms_tags, {
    Name = "${var.project_name}-${var.environment}-cis-${each.key}"
  })

  depends_on = [aws_cloudwatch_log_metric_filter.cis]
}
