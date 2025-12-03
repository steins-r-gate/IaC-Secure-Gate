# ==================================================================
# Foundation Module Outputs
# terraform/modules/foundation/outputs.tf
# ==================================================================

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key for log encryption"
  value       = aws_kms_key.logs.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for log encryption"
  value       = aws_kms_key.logs.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.logs.name
}

# CloudTrail Bucket Outputs
output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail logs bucket"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail logs bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

# Config Bucket Outputs
output "config_bucket_name" {
  description = "Name of the Config snapshots bucket"
  value       = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  description = "ARN of the Config snapshots bucket"
  value       = aws_s3_bucket.config.arn
}
