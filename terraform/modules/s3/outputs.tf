# ==================================================================
# terraform/modules/s3/outputs.tf
# ==================================================================

output "demo_bucket_name" {
  description = "Name of the demo S3 bucket"
  value       = aws_s3_bucket.demo.id
}

output "demo_bucket_arn" {
  description = "ARN of the demo S3 bucket"
  value       = aws_s3_bucket.demo.arn
}

output "demo_bucket_region" {
  description = "Region of the demo S3 bucket"
  value       = aws_s3_bucket.demo.region
}

# ============================================================================
# Optional outputs (for future expansion)
# ============================================================================

# output "kms_key_id" {
#   description = "ID of the KMS key"
#   value       = aws_kms_key.s3.key_id
# }

# output "cloudtrail_bucket_name" {
#   description = "Name of the CloudTrail bucket"
#   value       = aws_s3_bucket.cloudtrail.id
# }
