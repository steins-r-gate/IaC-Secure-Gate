# ==================================================================
# Outputs for the development environment
# terraform/environments/dev/outputs.tf
# ==================================================================

output "demo_bucket_name" {
  description = "Name of the demo S3 bucket"
  value       = module.s3.demo_bucket_name
}

output "demo_bucket_arn" {
  description = "ARN of the demo S3 bucket"
  value       = module.s3.demo_bucket_arn
}

output "demo_bucket_url" {
  description = "S3 console URL for the demo bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${module.s3.demo_bucket_name}"
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}
