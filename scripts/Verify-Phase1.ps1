Write-Host "`n🔍 Verifying Phase 1 Deployment" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

$checks = @{
    CloudTrail = $false
    Config = $false
    ConfigRules = $false
    AccessAnalyzer = $false
    SecurityHub = $false
    EventBridge = $false
}

# Check CloudTrail
Write-Host "`n1. CloudTrail Status:" -ForegroundColor Yellow
try {
    $trails = aws cloudtrail describe-trails --query 'trailList[?Name==`iam-security-audit-trail`]' | ConvertFrom-Json
    if ($trails.Count -gt 0) {
        $status = aws cloudtrail get-trail-status --name "iam-security-audit-trail" | ConvertFrom-Json
        if ($status.IsLogging) {
            Write-Host "  ✅ CloudTrail is logging" -ForegroundColor Green
            $checks.CloudTrail = $true
        } else {
            Write-Host "  ❌ CloudTrail not logging" -ForegroundColor Red
        }
    } else {
        Write-Host "  ❌ CloudTrail not found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Error checking CloudTrail: $_" -ForegroundColor Red
}

# Check Config
Write-Host "`n2. AWS Config Status:" -ForegroundColor Yellow
try {
    $recorders = aws configservice describe-configuration-recorder-status | ConvertFrom-Json
    if ($recorders.ConfigurationRecordersStatus.Count -gt 0) {
        $recorder = $recorders.ConfigurationRecordersStatus[0]
        if ($recorder.recording) {
            Write-Host "  ✅ Config is recording" -ForegroundColor Green
            $checks.Config = $true
        } else {
            Write-Host "  ❌ Config not recording" -ForegroundColor Red
        }
    } else {
        Write-Host "  ❌ Config recorder not found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Error checking Config: $_" -ForegroundColor Red
}

# Check Config Rules
Write-Host "`n3. Config Rules:" -ForegroundColor Yellow
try {
    $rules = aws configservice describe-config-rules --query 'ConfigRules[].ConfigRuleName' | ConvertFrom-Json
    if ($rules.Count -gt 0) {
        Write-Host "  ✅ $($rules.Count) Config rules found:" -ForegroundColor Green
        $rules | ForEach-Object { Write-Host "    - $_" -ForegroundColor Cyan }
        $checks.ConfigRules = $true
    } else {
        Write-Host "  ❌ No Config rules found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Error checking Config rules: $_" -ForegroundColor Red
}

# Check Access Analyzer
Write-Host "`n4. IAM Access Analyzer:" -ForegroundColor Yellow
try {
    $analyzers = aws accessanalyzer list-analyzers --query 'analyzers[?status==`ACTIVE`]' | ConvertFrom-Json
    if ($analyzers.Count -gt 0) {
        Write-Host "  ✅ Access Analyzer is active" -ForegroundColor Green
        $checks.AccessAnalyzer = $true
    } else {
        Write-Host "  ❌ No active analyzers found" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Error checking Access Analyzer: $_" -ForegroundColor Red
}

# Check Security Hub
Write-Host "`n5. Security Hub:" -ForegroundColor Yellow
try {
    $hub = aws securityhub describe-hub 2>$null | ConvertFrom-Json
    if ($hub.HubArn) {
        Write-Host "  ✅ Security Hub is enabled" -ForegroundColor Green
        $checks.SecurityHub = $true
        
        # Check standards
        $standards = aws securityhub describe-standards-subscriptions | ConvertFrom-Json
        Write-Host "  Standards enabled:" -ForegroundColor Cyan
        $standards.StandardsSubscriptions | ForEach-Object { 
            Write-Host "    - $($_.StandardsArn.Split('/')[-1])" -ForegroundColor Cyan 
        }
    } else {
        Write-Host "  ❌ Security Hub not enabled" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Error checking Security Hub: $_" -ForegroundColor Red
}

# Check EventBridge Rules
Write-Host "`n6. EventBridge Rules:" -ForegroundColor Yellow
try {
    $rules = aws events list-rules --query 'Rules[?State==`ENABLED`]' | ConvertFrom-Json
    $iamRules = $rules | Where-Object { $_.Name -like "*iam*" }
    if ($iamRules.Count -gt 0) {
        Write-Host "  ✅ $($iamRules.Count) IAM-related rules found:" -ForegroundColor Green
        $iamRules | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Cyan }
        $checks.EventBridge = $true
    } else {
        Write-Host "  ⚠️ No IAM-related EventBridge rules found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ❌ Error checking EventBridge: $_" -ForegroundColor Red
}

# Summary
Write-Host "`n📊 Verification Summary:" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
$passed = ($checks.Values | Where-Object { $_ -eq $true }).Count
$total = $checks.Count

$checks.GetEnumerator() | ForEach-Object {
    $status = if ($_.Value) { "✅" } else { "❌" }
    $color = if ($_.Value) { "Green" } else { "Red" }
    Write-Host "  $status $($_.Key)" -ForegroundColor $color
}

Write-Host "`nResult: $passed/$total checks passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })

if ($passed -eq $total) {
    Write-Host "`n🎉 Phase 1 is fully operational!" -ForegroundColor Green
} else {
    Write-Host "`n⚠️ Some components need attention" -ForegroundColor Yellow
}
