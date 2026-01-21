# ==================================================================
# Check Deployed AWS Resources for IaC-Secure-Gate Phase 1
# ==================================================================
# This script checks what Phase 1 resources are currently deployed
# Run from project root: .\scripts\check-deployed-resources.ps1
# ==================================================================

$Region = "eu-west-1"
$ProjectPrefix = "iam-secure-gate"
$Environment = "dev"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PHASE 1 DEPLOYMENT STATUS CHECK" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host "Project: $ProjectPrefix" -ForegroundColor Yellow
Write-Host "Environment: $Environment`n" -ForegroundColor Yellow

# ==================================================================
# 1. FOUNDATION MODULE
# ==================================================================
Write-Host "`n[1/5] FOUNDATION MODULE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

# KMS Key
Write-Host "`n  KMS Key:" -ForegroundColor White
try {
    $KmsAlias = aws kms list-aliases --region $Region --query "Aliases[?AliasName=='alias/$ProjectPrefix-$Environment-logs']" --output json | ConvertFrom-Json
    if ($KmsAlias) {
        Write-Host "    ✓ Alias: alias/$ProjectPrefix-$Environment-logs" -ForegroundColor Green
        Write-Host "    ✓ Key ID: $($KmsAlias[0].TargetKeyId)" -ForegroundColor Green

        # Check rotation
        $KeyId = $KmsAlias[0].TargetKeyId
        $RotationStatus = aws kms get-key-rotation-status --key-id $KeyId --region $Region --output json | ConvertFrom-Json
        if ($RotationStatus.KeyRotationEnabled) {
            Write-Host "    ✓ Auto-rotation: ENABLED" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Auto-rotation: DISABLED" -ForegroundColor Red
        }
    } else {
        Write-Host "    ✗ Not found" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ Error checking KMS key: $($_.Exception.Message)" -ForegroundColor Red
}

# S3 Buckets
Write-Host "`n  S3 Buckets:" -ForegroundColor White
$Buckets = @(
    @{Name="CloudTrail"; Pattern="$ProjectPrefix-$Environment-cloudtrail-*"},
    @{Name="Config"; Pattern="$ProjectPrefix-$Environment-config-*"}
)

foreach ($Bucket in $Buckets) {
    try {
        $BucketList = aws s3api list-buckets --query "Buckets[?starts_with(Name, '$($Bucket.Pattern.Replace('*',''))')].[Name]" --output text
        if ($BucketList) {
            Write-Host "    ✓ $($Bucket.Name): $BucketList" -ForegroundColor Green

            # Check encryption
            try {
                $Encryption = aws s3api get-bucket-encryption --bucket $BucketList --region $Region 2>$null
                if ($Encryption) {
                    Write-Host "      ✓ Encryption: ENABLED (KMS)" -ForegroundColor Green
                } else {
                    Write-Host "      ✗ Encryption: NOT CONFIGURED" -ForegroundColor Red
                }
            } catch {
                Write-Host "      ✗ Encryption: NOT CONFIGURED" -ForegroundColor Red
            }

            # Check versioning
            $Versioning = aws s3api get-bucket-versioning --bucket $BucketList --region $Region --output json | ConvertFrom-Json
            if ($Versioning.Status -eq "Enabled") {
                Write-Host "      ✓ Versioning: ENABLED" -ForegroundColor Green
            } else {
                Write-Host "      ✗ Versioning: NOT ENABLED" -ForegroundColor Red
            }
        } else {
            Write-Host "    ✗ $($Bucket.Name): Not found" -ForegroundColor Red
        }
    } catch {
        Write-Host "    ✗ $($Bucket.Name): Error - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ==================================================================
# 2. CLOUDTRAIL MODULE
# ==================================================================
Write-Host "`n[2/5] CLOUDTRAIL MODULE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

Write-Host "`n  Trail Status:" -ForegroundColor White
try {
    $TrailName = "$ProjectPrefix-$Environment-trail"
    $Trail = aws cloudtrail describe-trails --region $Region --query "trailList[?Name=='$TrailName']" --output json | ConvertFrom-Json

    if ($Trail) {
        Write-Host "    ✓ Trail Name: $TrailName" -ForegroundColor Green

        # Get trail status
        $Status = aws cloudtrail get-trail-status --name $TrailName --region $Region --output json | ConvertFrom-Json

        if ($Status.IsLogging) {
            Write-Host "    ✓ Logging Status: ACTIVE" -ForegroundColor Green
            Write-Host "    ✓ Last Log Delivery: $($Status.LatestDeliveryTime)" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Logging Status: INACTIVE" -ForegroundColor Red
        }

        # Check configuration
        if ($Trail[0].IsMultiRegionTrail) {
            Write-Host "    ✓ Multi-region: YES" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Multi-region: NO" -ForegroundColor Yellow
        }

        if ($Trail[0].LogFileValidationEnabled) {
            Write-Host "    ✓ Log Validation: ENABLED" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Log Validation: DISABLED" -ForegroundColor Red
        }

        if ($Trail[0].IncludeGlobalServiceEvents) {
            Write-Host "    ✓ Global Events: ENABLED" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Global Events: DISABLED" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    ✗ Trail not found: $TrailName" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ Error checking CloudTrail: $($_.Exception.Message)" -ForegroundColor Red
}

# ==================================================================
# 3. CONFIG MODULE
# ==================================================================
Write-Host "`n[3/5] CONFIG MODULE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

Write-Host "`n  Configuration Recorder:" -ForegroundColor White
try {
    $RecorderName = "$ProjectPrefix-$Environment-recorder"
    $Recorders = aws configservice describe-configuration-recorders --region $Region --output json | ConvertFrom-Json

    if ($Recorders.ConfigurationRecorders.Count -gt 0) {
        $Recorder = $Recorders.ConfigurationRecorders[0]
        Write-Host "    ✓ Recorder Name: $($Recorder.name)" -ForegroundColor Green

        # Check status
        $RecorderStatus = aws configservice describe-configuration-recorder-status --region $Region --output json | ConvertFrom-Json
        if ($RecorderStatus.ConfigurationRecordersStatus[0].recording) {
            Write-Host "    ✓ Recording Status: ACTIVE" -ForegroundColor Green
            Write-Host "    ✓ Last Status: $($RecorderStatus.ConfigurationRecordersStatus[0].lastStatus)" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Recording Status: INACTIVE" -ForegroundColor Red
        }
    } else {
        Write-Host "    ✗ No configuration recorder found" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ Error checking Config recorder: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n  Config Rules:" -ForegroundColor White
try {
    $Rules = aws configservice describe-config-rules --region $Region --output json | ConvertFrom-Json

    if ($Rules.ConfigRules.Count -gt 0) {
        Write-Host "    ✓ Total Rules: $($Rules.ConfigRules.Count)" -ForegroundColor Green

        # CIS-related rules
        $CISRules = @(
            "root-account-mfa-enabled",
            "iam-password-policy",
            "access-keys-rotated",
            "iam-user-mfa-enabled",
            "cloudtrail-enabled",
            "cloudtrail-log-file-validation-enabled",
            "s3-bucket-public-read-prohibited",
            "s3-bucket-public-write-prohibited"
        )

        Write-Host "`n    Expected Phase 1 CIS Rules:" -ForegroundColor White
        foreach ($RuleName in $CISRules) {
            $RuleExists = $Rules.ConfigRules | Where-Object { $_.ConfigRuleName -like "*$RuleName*" }
            if ($RuleExists) {
                Write-Host "      ✓ $RuleName" -ForegroundColor Green
            } else {
                Write-Host "      ✗ $RuleName - NOT FOUND" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "    ✗ No Config rules found" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ Error checking Config rules: $($_.Exception.Message)" -ForegroundColor Red
}

# ==================================================================
# 4. ACCESS ANALYZER MODULE
# ==================================================================
Write-Host "`n[4/5] ACCESS ANALYZER MODULE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

Write-Host "`n  Access Analyzer:" -ForegroundColor White
try {
    $Analyzers = aws accessanalyzer list-analyzers --region $Region --output json | ConvertFrom-Json

    if ($Analyzers.analyzers.Count -gt 0) {
        $Analyzer = $Analyzers.analyzers | Where-Object { $_.name -like "*$ProjectPrefix*$Environment*" } | Select-Object -First 1

        if ($Analyzer) {
            Write-Host "    ✓ Analyzer Name: $($Analyzer.name)" -ForegroundColor Green
            Write-Host "    ✓ Type: $($Analyzer.type)" -ForegroundColor Green
            Write-Host "    ✓ Status: $($Analyzer.status)" -ForegroundColor Green

            # Check for archive rules
            try {
                $ArchiveRules = aws accessanalyzer list-archive-rules --analyzer-name $Analyzer.name --region $Region --output json | ConvertFrom-Json
                if ($ArchiveRules.archiveRules.Count -gt 0) {
                    Write-Host "    ✓ Archive Rules: $($ArchiveRules.archiveRules.Count)" -ForegroundColor Green
                } else {
                    Write-Host "    - Archive Rules: 0" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "    - Archive Rules: Unable to check" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    ✗ Project analyzer not found" -ForegroundColor Red
        }
    } else {
        Write-Host "    ✗ No Access Analyzer found" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ Error checking Access Analyzer: $($_.Exception.Message)" -ForegroundColor Red
}

# ==================================================================
# 5. SECURITY HUB MODULE
# ==================================================================
Write-Host "`n[5/5] SECURITY HUB MODULE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

Write-Host "`n  Security Hub Status:" -ForegroundColor White
try {
    $Hub = aws securityhub describe-hub --region $Region 2>$null

    if ($Hub) {
        Write-Host "    ✓ Security Hub: ENABLED" -ForegroundColor Green

        # Check enabled standards
        $Standards = aws securityhub get-enabled-standards --region $Region --output json | ConvertFrom-Json
        if ($Standards.StandardsSubscriptions.Count -gt 0) {
            Write-Host "`n    Enabled Standards:" -ForegroundColor White
            foreach ($Standard in $Standards.StandardsSubscriptions) {
                $StandardName = $Standard.StandardsArn -replace '.*standards/', ''
                Write-Host "      ✓ $StandardName" -ForegroundColor Green
                Write-Host "        Status: $($Standard.StandardsStatus)" -ForegroundColor Gray
            }
        } else {
            Write-Host "    ✗ No standards enabled" -ForegroundColor Yellow
        }

        # Check product subscriptions
        Write-Host "`n    Product Integrations:" -ForegroundColor White
        try {
            $Products = aws securityhub list-enabled-products-for-import --region $Region --output json 2>$null | ConvertFrom-Json
            if ($Products -and $Products.ProductSubscriptions.Count -gt 0) {
                foreach ($Product in $Products.ProductSubscriptions) {
                    $ProductName = $Product -replace '.*product/', '' -replace '/default', ''
                    Write-Host "      ✓ $ProductName" -ForegroundColor Green
                }
            } else {
                Write-Host "      - No product integrations" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "      - Unable to check integrations" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    ✗ Security Hub: NOT ENABLED" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ Security Hub: NOT ENABLED (or error checking)" -ForegroundColor Red
}

# ==================================================================
# SUMMARY
# ==================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Run these commands for more details:`n" -ForegroundColor Yellow

Write-Host "# Check specific CloudTrail events" -ForegroundColor Gray
Write-Host "aws cloudtrail lookup-events --region $Region --max-results 5`n" -ForegroundColor White

Write-Host "# Check Config compliance" -ForegroundColor Gray
Write-Host "aws configservice describe-compliance-by-config-rule --region $Region`n" -ForegroundColor White

Write-Host "# List Access Analyzer findings" -ForegroundColor Gray
Write-Host "aws accessanalyzer list-findings --analyzer-arn <analyzer-arn> --region $Region`n" -ForegroundColor White

Write-Host "# Check Security Hub findings" -ForegroundColor Gray
Write-Host "aws securityhub get-findings --region $Region --max-items 5`n" -ForegroundColor White

Write-Host "# Verify terraform plan matches deployed resources" -ForegroundColor Gray
Write-Host "cd terraform/environments/dev && terraform plan`n" -ForegroundColor White

Write-Host "`n========================================`n" -ForegroundColor Cyan
