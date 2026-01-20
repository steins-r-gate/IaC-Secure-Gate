# ==================================================================
# Foundation Module - Local Values and Data Sources
# terraform/modules/foundation/locals.tf
# ==================================================================

locals {
  # Auto-detect account ID and region (removes need for variables)
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # Bucket naming with global uniqueness
  cloudtrail_bucket_name = "${var.project_name}-${var.environment}-cloudtrail-${local.account_id}"
  config_bucket_name     = "${var.project_name}-${var.environment}-config-${local.account_id}"

  # Common tags for all foundation resources
  foundation_tags = merge(var.common_tags, {
    Module  = "foundation"
    Phase   = "Phase-1-Detection"
    Service = "Foundation"
  })

  # CloudTrail-specific tags
  cloudtrail_tags = merge(local.foundation_tags, {
    Name    = "CloudTrail Logs Bucket"
    Service = "CloudTrail"
  })

  # Config-specific tags
  config_tags = merge(local.foundation_tags, {
    Name    = "AWS Config Snapshots Bucket"
    Service = "Config"
  })
}
