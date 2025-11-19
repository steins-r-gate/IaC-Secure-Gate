output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_bucket_arn" {
  value = aws_s3_bucket.cloudtrail.arn
}

output "config_bucket_name" {
  value = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  value = aws_s3_bucket.config.arn
}
