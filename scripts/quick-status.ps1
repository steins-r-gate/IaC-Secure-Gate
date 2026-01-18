# IAM-Secure-Gate - Quick Deployment Status Check
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " IAM-Secure-Gate Deployment Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. AWS Connection
Write-Host "[1/6] AWS Connection..." -ForegroundColor Yellow
$identity = aws sts get-caller-identity --output json | ConvertFrom-Json
Write-Host "Connected: $($identity.Arn)" -ForegroundColor Green
Write-Host ""

# 2. KMS Keys
Write-Host "[2/6] KMS Keys..." -ForegroundColor Yellow
$aliases = aws kms list-aliases --region eu-west-1 --output json | ConvertFrom-Json
$kmsKey = $aliases.Aliases | Where-Object { $_.AliasName -like "*iam-secure*" }
if ($kmsKey) {
    Write-Host "Found: $($kmsKey.AliasName)" -ForegroundColor Green
} else {
    Write-Host "Not found" -ForegroundColor Red
}
Write-Host ""

# 3. S3 Buckets
Write-Host "[3/6] S3 Buckets..." -ForegroundColor Yellow
$buckets = aws s3 ls | Select-String "iam-secure-gate"
if ($buckets) {
    $buckets | ForEach-Object {
        $name = ($_ -split '\s+')[-1]
        Write-Host "Found: $name" -ForegroundColor Green
    }
} else {
    Write-Host "Not found" -ForegroundColor Red
}
Write-Host ""

# 4. CloudTrail
Write-Host "[4/6] CloudTrail..." -ForegroundColor Yellow
$trails = aws cloudtrail describe-trails --region eu-west-1 --output json | ConvertFrom-Json
$trail = $trails.trailList | Where-Object { $_.Name -like "*iam-secure*" }
if ($trail) {
    Write-Host "Found: $($trail.Name)" -ForegroundColor Green
    $status = aws cloudtrail get-trail-status --name $trail.Name --region eu-west-1 --output json | ConvertFrom-Json
    Write-Host "Logging: $($status.IsLogging)" -ForegroundColor Gray
} else {
    Write-Host "Not found" -ForegroundColor Red
}
Write-Host ""

# 5. AWS Config
Write-Host "[5/6] AWS Config..." -ForegroundColor Yellow
$recorder = aws configservice describe-configuration-recorders --region eu-west-1 --output json | ConvertFrom-Json
if ($recorder.ConfigurationRecorders) {
    Write-Host "Found: $($recorder.ConfigurationRecorders[0].name)" -ForegroundColor Green
    $rules = aws configservice describe-config-rules --region eu-west-1 --output json | ConvertFrom-Json
    Write-Host "Config Rules: $($rules.ConfigRules.Count)" -ForegroundColor Gray
} else {
    Write-Host "Not found" -ForegroundColor Red
}
Write-Host ""

# 6. Security Hub & IAM Access Analyzer
Write-Host "[6/6] Security Hub & IAM Access Analyzer..." -ForegroundColor Yellow
try {
    $hub = aws securityhub describe-hub --region eu-west-1 --output json 2>$null | ConvertFrom-Json
    if ($hub) {
        Write-Host "Security Hub: Enabled" -ForegroundColor Green
    }
} catch {
    Write-Host "Security Hub: Not enabled" -ForegroundColor Yellow
}

try {
    $analyzers = aws accessanalyzer list-analyzers --region eu-west-1 --output json 2>$null | ConvertFrom-Json
    if ($analyzers.analyzers) {
        Write-Host "IAM Access Analyzer: $($analyzers.analyzers.Count) found" -ForegroundColor Green
    }
} catch {
    Write-Host "IAM Access Analyzer: Not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Check Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan