# Set AWS Environment Variables
$env:AWS_PROFILE = "IAM-Secure-Gate"
$env:AWS_REGION  = "eu-west-1"
$env:AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

Write-Host "AWS Environment Set:" -ForegroundColor Green
Write-Host "  Profile: $env:AWS_PROFILE" -ForegroundColor Cyan
Write-Host "  Region:  $env:AWS_REGION" -ForegroundColor Cyan
Write-Host "  Account: $env:AWS_ACCOUNT_ID" -ForegroundColor Cyan
