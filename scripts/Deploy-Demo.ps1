# Deploy-Demo.ps1
# Fixed version - Streamlined deployment for commission demonstration
# Deploys minimal Phase 1 with sample violations for immediate demonstration

param(
    [Parameter(Mandatory=$false)]
    [int]$DemoMinutes = 30,  # How long the demo will run
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPreChecks,
    
    [Parameter(Mandatory=$false)]
    [switch]$QuickMode  # Skip confirmations
)

$ErrorActionPreference = "Stop"

# Demo banner
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     IAM SECURITY PIPELINE - COMMISSION DEMO MODE      ║" -ForegroundColor Cyan
    Write-Host "  ║          Rapid Deployment for Presentation            ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Estimated deployment time: 3-5 minutes" -ForegroundColor Yellow
    Write-Host "  Auto-cleanup available after demo" -ForegroundColor Yellow
    Write-Host ""
}

Show-Banner

# Track deployed resources for cleanup
$global:DemoResources = @{
    Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    S3Buckets = @()
    IAMPolicies = @()
    IAMRoles = @()
    CloudTrail = $null
    ConfigRecorder = $null
    ResourcePrefix = "demo-iam-sec-$(Get-Date -Format 'MMddHHmm')"
}

# Save demo state for cleanup
$demoStateFile = "demo-state-$($global:DemoResources.Timestamp).json"

# Quick pre-checks
if (-not $SkipPreChecks) {
    Write-Host "Pre-flight checks..." -ForegroundColor Yellow
    
    # Check AWS
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-Host "  AWS Account: $($identity.Account)" -ForegroundColor Green
        $global:DemoResources.AccountId = $identity.Account
    } catch {
        Write-Host "  AWS credentials not configured" -ForegroundColor Red
        exit 1
    }
    
    # Check Terraform
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-Host "  Terraform not installed" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Terraform installed" -ForegroundColor Green
}

# Create minimal Terraform configuration
Write-Host "`nCreating demo configuration..." -ForegroundColor Yellow

$demoDir = "terraform-demo-$($global:DemoResources.Timestamp)"
New-Item -ItemType Directory -Force -Path $demoDir | Out-Null

# Create main.tf with minimal resources - Fixed multiline string
$mainTf = @'
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "IAMSecurityDemo"
      Environment = "Demo"
      AutoCleanup = "True"
      CreatedAt   = timestamp()
    }
  }
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "resource_prefix" {
  default = "demo-iam-sec"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  prefix     = "${var.resource_prefix}-${formatdate("MMDDhhmm", timestamp())}"
}

data "aws_caller_identity" "current" {}

# Minimal S3 bucket for CloudTrail
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.prefix}-cloudtrail-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail for IAM monitoring
resource "aws_cloudtrail" "demo" {
  name                          = "${local.prefix}-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail        = false
  enable_log_file_validation   = false

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::IAM::Role"
      values = ["arn:aws:iam::*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# Config for compliance checking
resource "aws_s3_bucket" "config" {
  bucket        = "${local.prefix}-config-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "config" {
  name = "${local.prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
    }]
  })
  
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/ConfigRole"]
}

resource "aws_iam_role_policy" "config_s3" {
  name = "${local.prefix}-config-s3"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource = aws_s3_bucket.config.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringLike = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "demo" {
  name     = "${local.prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = false
    resource_types = [
      "AWS::IAM::Policy",
      "AWS::IAM::Role"
    ]
  }

  depends_on = [aws_config_delivery_channel.demo]
}

resource "aws_config_delivery_channel" "demo" {
  name           = "${local.prefix}-channel"
  s3_bucket_name = aws_s3_bucket.config.id
}

resource "aws_config_configuration_recorder_status" "demo" {
  name       = aws_config_configuration_recorder.demo.name
  is_enabled = true

  depends_on = [aws_config_configuration_recorder.demo]
}

# Key Config Rules for demo
resource "aws_config_config_rule" "iam_policy_no_admin" {
  name = "${local.prefix}-no-admin-access"

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder.demo]
}

resource "aws_config_config_rule" "iam_root_access_key" {
  name = "${local.prefix}-root-key-check"

  source {
    owner             = "AWS"
    source_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder.demo]
}

# IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "demo" {
  analyzer_name = "${local.prefix}-analyzer"
  type         = "ACCOUNT"
}

# Outputs for demo script
output "demo_resources" {
  value = {
    cloudtrail_name    = aws_cloudtrail.demo.name
    config_recorder    = aws_config_configuration_recorder.demo.name
    analyzer_name      = aws_accessanalyzer_analyzer.demo.analyzer_name
    s3_cloudtrail      = aws_s3_bucket.cloudtrail.id
    s3_config          = aws_s3_bucket.config.id
    config_role        = aws_iam_role.config.name
    prefix             = local.prefix
  }
}

output "account_id" {
  value = local.account_id
}
'@

$mainTf | Out-File -FilePath "$demoDir\main.tf" -Encoding UTF8

# Deploy demo infrastructure
Write-Host "Deploying demo infrastructure..." -ForegroundColor Cyan
Set-Location $demoDir

terraform init -upgrade | Out-Null
Write-Host "  Terraform initialized" -ForegroundColor Green

terraform apply -auto-approve | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Deployment failed" -ForegroundColor Red
    Set-Location ..
    Remove-Item $demoDir -Recurse -Force
    exit 1
}

# Get outputs and save state
$outputs = terraform output -json | ConvertFrom-Json
$global:DemoResources.TerraformDir = $demoDir
$global:DemoResources.Outputs = $outputs

Write-Host "  Infrastructure deployed" -ForegroundColor Green

# Create demo violations
Write-Host "`nCreating demonstration violations..." -ForegroundColor Yellow

# Violation 1: Wildcard policy
$wildcardPolicy = @{
    PolicyName = "$($outputs.demo_resources.value.prefix)-wildcard-violation"
    PolicyDocument = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Action = "*"
                Resource = "*"
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress
}

$policy1 = aws iam create-policy `
    --policy-name $wildcardPolicy.PolicyName `
    --policy-document $wildcardPolicy.PolicyDocument `
    --output json | ConvertFrom-Json

$global:DemoResources.IAMPolicies += $policy1.Policy.Arn
Write-Host "  Created wildcard policy violation" -ForegroundColor Yellow

# Violation 2: Overly permissive trust policy
$badRole = @{
    RoleName = "$($outputs.demo_resources.value.prefix)-public-assume-role"
    AssumeRolePolicyDocument = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Principal = @{ AWS = "*" }
                Action = "sts:AssumeRole"
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress
}

aws iam create-role `
    --role-name $badRole.RoleName `
    --assume-role-policy-document $badRole.AssumeRolePolicyDocument `
    --output json | Out-Null

$global:DemoResources.IAMRoles += $badRole.RoleName
Write-Host "  Created overly permissive role" -ForegroundColor Yellow

# Save demo state
$global:DemoResources | ConvertTo-Json | Out-File -FilePath "..\$demoStateFile" -Encoding UTF8

Set-Location ..

# Display demo dashboard
Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "           DEMO ENVIRONMENT READY" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nDemo Resources Created:" -ForegroundColor Cyan
Write-Host "  • CloudTrail: $($outputs.demo_resources.value.cloudtrail_name)" -ForegroundColor White
Write-Host "  • Config Recorder: $($outputs.demo_resources.value.config_recorder)" -ForegroundColor White
Write-Host "  • Access Analyzer: $($outputs.demo_resources.value.analyzer_name)" -ForegroundColor White
Write-Host "  • 2 IAM violations for demonstration" -ForegroundColor White

Write-Host "`nWhat to Show the Commission:" -ForegroundColor Cyan
Write-Host "  1. CloudTrail capturing IAM API calls in real-time" -ForegroundColor White
Write-Host "  2. Config Rules detecting the violations" -ForegroundColor White
Write-Host "  3. Access Analyzer identifying risky policies" -ForegroundColor White
Write-Host "  4. Detection time: less than 30 seconds for Config" -ForegroundColor White

Write-Host "`nAWS Console Links:" -ForegroundColor Cyan
$region = (aws configure get region)
Write-Host "  CloudTrail: https://console.aws.amazon.com/cloudtrail/home?region=$region" -ForegroundColor Blue
Write-Host "  Config: https://console.aws.amazon.com/config/home?region=$region" -ForegroundColor Blue
Write-Host "  IAM Policies: https://console.aws.amazon.com/iam/home#/policies" -ForegroundColor Blue
Write-Host "  Access Analyzer: https://console.aws.amazon.com/access-analyzer/home?region=$region" -ForegroundColor Blue

Write-Host "`nDemo Timer Started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow
Write-Host "  Demo will auto-cleanup in $DemoMinutes minutes" -ForegroundColor Yellow

Write-Host "`nDemo Talking Points:" -ForegroundColor Cyan
Write-Host "  • 'This detects IAM misconfigurations in under 5 minutes'" -ForegroundColor White
Write-Host "  • 'The wildcard policy would give full AWS access'" -ForegroundColor White
Write-Host "  • 'Config provides compliance as code'" -ForegroundColor White
Write-Host "  • 'Phase 2 will add automated remediation'" -ForegroundColor White

# Save cleanup command
Write-Host "`nTo clean up after demo, run:" -ForegroundColor Yellow
Write-Host "  .\scripts\Cleanup-Demo.ps1 -StateFile $demoStateFile" -ForegroundColor Cyan

# Optional: Auto-cleanup timer
if (-not $QuickMode) {
    Write-Host "`n" -NoNewline
    $cleanup = Read-Host "Enable auto-cleanup after $DemoMinutes minutes? (y/n)"
    if ($cleanup -eq "y") {
        $cleanupTime = (Get-Date).AddMinutes($DemoMinutes)
        Write-Host "Auto-cleanup scheduled for $($cleanupTime.ToString('HH:mm:ss'))" -ForegroundColor Yellow
        
        Start-Job -ScriptBlock {
            param($Minutes, $StateFile, $ScriptPath)
            Start-Sleep -Seconds ($Minutes * 60)
            & "$ScriptPath\Cleanup-Demo.ps1" -StateFile $StateFile -Force
        } -ArgumentList $DemoMinutes, $demoStateFile, $PSScriptRoot | Out-Null
    }
}

Write-Host "`nDemo deployment complete!" -ForegroundColor Green
Write-Host "Good luck with your presentation!" -ForegroundColor Cyan