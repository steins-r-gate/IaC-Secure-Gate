# ==================================================================
# CloudTrail Module - Main Resources
# terraform/modules/cloudtrail/main.tf
# Purpose: Create CloudTrail trail for IAM activity logging
# ==================================================================

locals {
  trail_name = "${var.project_name}-${var.environment}-trail"
  
  # Common tags for all CloudTrail resources
  cloudtrail_tags = merge(var.common_tags, {
    Module  = "cloudtrail"
    Service = "CloudTrail"
  })
}

# ==================================================================
# CloudTrail Trail
# ==================================================================

resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = var.cloudtrail_bucket_name
  kms_key_id                    = var.kms_key_id
  
  # Security settings
  enable_log_file_validation    = var.enable_log_file_validation
  is_multi_region_trail         = var.is_multi_region_trail
  include_global_service_events = var.include_global_service_events
  
  # Event selectors for management events (IAM API calls)
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    # Log all management events (including IAM)
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*/"]
    }
  }
  
  tags = merge(local.cloudtrail_tags, {
    Name = local.trail_name
  })
  
  # Ensure KMS key policy is ready before creating trail
  depends_on = [var.kms_key_id]
}
