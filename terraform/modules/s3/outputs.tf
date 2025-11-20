# s3/outputs.tf

# ============================================================================
# CloudTrail Outputs
# ============================================================================
output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

# ============================================================================
# Config Outputs
# ============================================================================
output "config_bucket_name" {
  description = "Name of the AWS Config S3 bucket"
  value       = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  description = "ARN of the AWS Config S3 bucket"
  value       = aws_s3_bucket.config.arn
}

# ============================================================================
# Logs Bucket Outputs
# ============================================================================
output "logs_bucket_name" {
  description = "Name of the S3 access logs bucket"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "ARN of the S3 access logs bucket"
  value       = aws_s3_bucket.logs.arn
}

# ============================================================================
# KMS Key Outputs
# ============================================================================
output "kms_key_id" {
  description = "ID of the KMS key used for S3 encryption"
  value       = aws_kms_key.s3.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption"
  value       = aws_kms_key.s3.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for S3 encryption"
  value       = aws_kms_alias.s3.name
}
