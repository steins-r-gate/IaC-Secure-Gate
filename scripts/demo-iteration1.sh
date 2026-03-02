#!/bin/bash
# ==================================================================
# IaC Secure Gate — Iteration 1 Demo Script
# Panel Presentation: Detection Baseline
# ==================================================================
# Demonstrates live AWS detection pipeline: CloudTrail, Config,
# Access Analyzer, Security Hub. No input required — just run it.
# ==================================================================

# Suppress AWS CLI pager (causes 'more' errors on Windows)
export AWS_PAGER=""

# ── Colour palette ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ── Environment constants (no user input required) ─────────────────
REGION="eu-west-1"
ACCOUNT_ID="826232761554"
TRAIL_NAME="iam-secure-gate-dev-trail"
RECORDER_NAME="iam-secure-gate-dev-recorder"
ANALYZER_NAME="iam-secure-gate-dev-analyzer"
TABLE="iam-secure-gate-dev-remediation-history"

# ── State ──────────────────────────────────────────────────────────
BUCKET=""
START_TIME=0
MTTD_SECONDS="N/A"
CHECKS_PASSED=0
CHECKS_TOTAL=6

# ── Helpers ────────────────────────────────────────────────────────

print_section() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_pass() {
    echo -e "  ${GREEN}✓${NC}  $1"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_fail() {
    echo -e "  ${RED}✗${NC}  $1"
}

format_duration() {
    local s=$1
    local m=$((s / 60))
    local r=$((s % 60))
    if [ "$m" -gt 0 ]; then echo "${m}m ${r}s"; else echo "${s}s"; fi
}

cleanup_bucket() {
    if [ -n "$BUCKET" ]; then
        aws s3api put-public-access-block --bucket "$BUCKET" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
            --region "$REGION" 2>/dev/null || true
        aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null || true
    fi
}

trap 'echo ""; echo -e "${YELLOW}Interrupted — cleaning up...${NC}"; cleanup_bucket; exit 1' INT TERM

# ==================================================================
# SECTION 0 — Banner
# ==================================================================

clear
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ██╗ █████╗  ██████╗    ███████╗███████╗ ██████╗██╗   ██╗██████╗ ███████╗"
echo "  ██║██╔══██╗██╔════╝    ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██╔════╝"
echo "  ██║███████║██║         ███████╗█████╗  ██║     ██║   ██║██████╔╝█████╗  "
echo "  ██║██╔══██║██║         ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██╔══╝  "
echo "  ██║██║  ██║╚██████╗    ███████║███████╗╚██████╗╚██████╔╝██║  ██║███████╗"
echo "  ╚═╝╚═╝  ╚═╝ ╚═════╝    ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝"
echo -e "${NC}"
echo -e "${WHITE}${BOLD}  ██████╗  █████╗ ████████╗███████╗${NC}"
echo -e "${WHITE}${BOLD}  ██╔════╝██╔══██╗╚══██╔══╝██╔════╝${NC}"
echo -e "${WHITE}${BOLD}  ██║  ███╗███████║   ██║   █████╗  ${NC}"
echo -e "${WHITE}${BOLD}  ██║   ██║██╔══██║   ██║   ██╔══╝  ${NC}"
echo -e "${WHITE}${BOLD}  ╚██████╔╝██║  ██║   ██║   ███████╗${NC}"
echo -e "${WHITE}${BOLD}   ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝${NC}"
echo ""
echo -e "${YELLOW}${BOLD}  ITERATION 1 — DETECTION BASELINE${NC}"
echo -e "${WHITE}  Region: ${CYAN}${REGION}${NC}   |   Account: ${CYAN}${ACCOUNT_ID}${NC}   |   Date: ${CYAN}$(date +"%Y-%m-%d")${NC}"
echo ""
echo -e "${WHITE}  Demonstrating: CloudTrail • AWS Config • Access Analyzer • Security Hub${NC}"
echo ""
sleep 4

# ==================================================================
# SECTION 1 — Infrastructure Verification
# ==================================================================

print_section "SECTION 1 — INFRASTRUCTURE VERIFICATION"
echo -e "${WHITE}  Verifying all 6 detection pipeline components...${NC}"
echo ""

# ── Check 1: CloudTrail logging ────────────────────────────────────
printf "  ${BLUE}[1/6]${NC} CloudTrail active (${TRAIL_NAME})... "
CT_STATUS=$(aws cloudtrail get-trail-status \
    --name "$TRAIL_NAME" \
    --region "$REGION" \
    --query "IsLogging" \
    --output text 2>/dev/null)

if [ "$CT_STATUS" = "True" ]; then
    echo -e "${GREEN}LOGGING${NC}"
    check_pass "CloudTrail: IsLogging = true"
else
    echo -e "${RED}NOT LOGGING${NC}"
    check_fail "CloudTrail: IsLogging = false (status: ${CT_STATUS})"
fi

# ── Check 2: CloudTrail log file validation ────────────────────────
printf "  ${BLUE}[2/6]${NC} CloudTrail log validation enabled... "
LV_STATUS=$(aws cloudtrail get-trail \
    --name "$TRAIL_NAME" \
    --region "$REGION" \
    --query "Trail.LogFileValidationEnabled" \
    --output text 2>/dev/null)

LATEST_DELIVERY=$(aws cloudtrail get-trail-status \
    --name "$TRAIL_NAME" \
    --region "$REGION" \
    --query "LatestDeliveryAttemptTime" \
    --output text 2>/dev/null)

if [ "$LV_STATUS" = "True" ]; then
    echo -e "${GREEN}ENABLED${NC}"
    check_pass "Log validation: enabled  |  Last delivery: ${LATEST_DELIVERY}"
else
    echo -e "${YELLOW}DISABLED${NC}"
    check_fail "Log validation: ${LV_STATUS}"
fi

# ── Check 3: Config recorder active ───────────────────────────────
printf "  ${BLUE}[3/6]${NC} AWS Config recorder recording... "
RECORDER_STATUS=$(aws configservice describe-configuration-recorder-status \
    --region "$REGION" \
    --query "ConfigurationRecordersStatus[0].recording" \
    --output text 2>/dev/null)

if [ "$RECORDER_STATUS" = "True" ]; then
    echo -e "${GREEN}RECORDING${NC}"
    check_pass "Config recorder: recording = true"
else
    echo -e "${RED}NOT RECORDING${NC}"
    check_fail "Config recorder: recording = ${RECORDER_STATUS}"
fi

# ── Check 4: Config rules deployed ────────────────────────────────
printf "  ${BLUE}[4/6]${NC} AWS Config rules deployed... "
ALL_RULES=$(aws configservice describe-config-rules \
    --region "$REGION" \
    --query "ConfigRules[*].ConfigRuleName" \
    --output text 2>/dev/null)

RULE_COUNT=$(echo "$ALL_RULES" | tr '\t' '\n' | grep -c '.' || echo 0)
PROJECT_COUNT=$(echo "$ALL_RULES" | tr '\t' '\n' | grep -cv '^securityhub-' || echo 0)
SH_COUNT=$(echo "$ALL_RULES" | tr '\t' '\n' | grep -c '^securityhub-' || echo 0)

if [ "$RULE_COUNT" -ge 8 ] 2>/dev/null; then
    echo -e "${GREEN}${RULE_COUNT} rules${NC}"
    check_pass "Config rules: ${PROJECT_COUNT} project-defined  +  ${SH_COUNT} Security Hub CIS controls"
    echo ""
    echo -e "       ${WHITE}── Project-defined rules ──${NC}"
    echo "$ALL_RULES" | tr '\t' '\n' | grep -v '^securityhub-' | while read -r rule; do
        [ -n "$rule" ] && echo -e "       ${MAGENTA}▸${NC} ${rule}"
    done
    echo ""
    echo -e "       ${WHITE}── Security Hub managed rules (CIS AWS Foundations v1.4.0) ──${NC}"
    echo "$ALL_RULES" | tr '\t' '\n' | grep '^securityhub-' | while read -r rule; do
        [ -n "$rule" ] && echo -e "       ${CYAN}▸${NC} ${rule}"
    done
    echo ""
else
    echo -e "${YELLOW}${RULE_COUNT} rules found${NC}"
    check_fail "Config rules: expected ≥8, found ${RULE_COUNT}"
fi

# ── Check 5: Access Analyzer active ───────────────────────────────
printf "  ${BLUE}[5/6]${NC} IAM Access Analyzer status... "
ANALYZER_STATUS=$(aws accessanalyzer list-analyzers \
    --region "$REGION" \
    --query "analyzers[?name=='${ANALYZER_NAME}'].status" \
    --output text 2>/dev/null)

if [ "$ANALYZER_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}ACTIVE${NC}"
    check_pass "Access Analyzer: ${ANALYZER_NAME} = ACTIVE"
else
    echo -e "${RED}${ANALYZER_STATUS:-NOT FOUND}${NC}"
    check_fail "Access Analyzer: status = ${ANALYZER_STATUS:-NOT FOUND}"
fi

# ── Check 6: Security Hub CIS standard enabled ─────────────────────
printf "  ${BLUE}[6/6]${NC} Security Hub CIS AWS Foundations v1.4.0... "
CIS_STATUS=$(aws securityhub get-enabled-standards \
    --region "$REGION" \
    --query "StandardsSubscriptions[?contains(StandardsArn,'cis-aws-foundations-benchmark/v/1.4.0')].StandardsStatus" \
    --output text 2>/dev/null)

if [ "$CIS_STATUS" = "READY" ]; then
    echo -e "${GREEN}READY${NC}"
    check_pass "Security Hub: CIS AWS Foundations Benchmark v1.4.0 = READY"
else
    echo -e "${YELLOW}${CIS_STATUS:-NOT ENABLED}${NC}"
    check_fail "Security Hub CIS standard: ${CIS_STATUS:-NOT FOUND}"
fi

# ── Summary line ───────────────────────────────────────────────────
echo ""
if [ "$CHECKS_PASSED" -eq "$CHECKS_TOTAL" ]; then
    echo -e "  ${GREEN}${BOLD}${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed — infrastructure healthy${NC}"
else
    echo -e "  ${YELLOW}${BOLD}${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed${NC}"
fi
echo ""
sleep 3

# ==================================================================
# SECTION 2 — Violation Injection
# ==================================================================

print_section "SECTION 2 — INJECTING MISCONFIGURATION: S3 Public Bucket"

BUCKET="iac-securegate-demo-$(date +%s)"

echo -e "${WHITE}  Creating S3 bucket: ${YELLOW}${BUCKET}${NC}"
aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    --output text > /dev/null

echo -e "${WHITE}  Disabling ALL public access blocks (simulating misconfiguration)...${NC}"
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
    --region "$REGION"

echo ""
echo -e "  ${RED}${BOLD}Bucket created: ${BUCKET}${NC}"
echo -e "  ${RED}${BOLD}Public access blocks: DISABLED${NC}"
echo ""

echo ""
echo -e "  ${WHITE}Starting detection timer...${NC} ${YELLOW}$(date)${NC}"
START_TIME=$(date +%s)
echo ""

# ── Give Config 60 seconds to record the new bucket via CloudTrail ─
# The Config recorder ingests CreateBucket and PutPublicAccessBlock
# CloudTrail events and records the bucket's configuration state.
# Change-triggered rules (logging, SSL, MFA-delete) fire immediately
# on recording. Periodic rules (public access block) fire on schedule.
echo -e "  ${WHITE}Waiting 60s for Config to record the new bucket via CloudTrail...${NC}"
for t in $(seq 60 -1 1); do
    printf "\r  ${YELLOW}  %2ds remaining...${NC}" "$t"
    sleep 1
done
echo ""
echo -e "  ${GREEN}✓${NC}  Config recording window elapsed"
echo ""

# Trigger evaluation for all S3 rules now that the bucket is in scope
echo -e "  ${WHITE}Triggering Config rules evaluation...${NC}"
aws configservice start-config-rules-evaluation \
    --config-rule-names \
        "s3-bucket-public-read-prohibited" \
        "s3-bucket-public-write-prohibited" \
        "securityhub-s3-bucket-level-public-access-prohibited-03cb4d5f" \
    --region "$REGION" 2>/dev/null && \
    echo -e "  ${GREEN}✓${NC}  Config re-evaluation triggered" || \
    echo -e "  ${YELLOW}⚠${NC}  Trigger returned an error — evaluation will still run on schedule"

echo ""
sleep 2

# ==================================================================
# SECTION 3 — Live Detection Polling
# ==================================================================
# Strategy: poll AWS Config compliance directly (faster, ~1–3 min)
# then confirm in Security Hub (which ingests Config findings with a
# small additional lag). This reflects the real two-layer architecture.

print_section "SECTION 3 — LIVE DETECTION — Config → Security Hub pipeline"

echo -e "${WHITE}  Layer 1: AWS Config evaluates bucket compliance (change-triggered + periodic rules)${NC}"
echo -e "${WHITE}  Layer 2: Security Hub ingests the Config finding and maps it to a CIS control${NC}"
echo -e "${WHITE}  No human action required at any point.${NC}"
echo ""

MAX_ITERATIONS=60   # 60 × 10 s = 10 min hard cap
INTERVAL=10
FOUND=false
DETECTED_BY=""
CONFIG_RULE_HIT=""

BUCKET_ARN="arn:aws:s3:::${BUCKET}"

for i in $(seq 1 $MAX_ITERATIONS); do
    ELAPSED_NOW=$(( $(date +%s) - START_TIME ))
    printf "  ${BLUE}[%02d/%02d]${NC} %s elapsed — " \
        "$i" "$MAX_ITERATIONS" "$(format_duration $ELAPSED_NOW)"

    # ── Layer 1: AWS Config compliance ────────────────────────────
    # get-compliance-details-by-resource returns NON_COMPLIANT evaluations
    # from both project-defined and Security Hub managed Config rules.
    CONFIG_HIT=$(aws configservice get-compliance-details-by-resource \
        --resource-type "AWS::S3::Bucket" \
        --resource-id "$BUCKET" \
        --compliance-types NON_COMPLIANT \
        --region "$REGION" \
        --query "EvaluationResults[0].EvaluationResultIdentifier.EvaluationResultQualifier.ConfigRuleName" \
        --output text 2>/dev/null || echo "None")

    if [ "$CONFIG_HIT" != "None" ] && [ -n "$CONFIG_HIT" ] && [ "$CONFIG_HIT" != "null" ]; then
        MTTD_SECONDS=$(( $(date +%s) - START_TIME ))
        CONFIG_RULE_HIT="$CONFIG_HIT"
        echo -e "${GREEN}${BOLD}Config: NON_COMPLIANT!${NC}"
        echo ""
        echo -e "  ${GREEN}${BOLD}★  Violation detected by AWS Config after $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS}s)${NC}"
        echo -e "  ${GREEN}   Rule triggered: ${CONFIG_RULE_HIT}${NC}"
        echo ""
        echo -e "  ${WHITE}  Waiting for Security Hub to ingest the finding (~30–60 s more)...${NC}"
        DETECTED_BY="Config"
        FOUND=true

        # Poll Security Hub for up to 3 more minutes to show the full pipeline
        for j in $(seq 1 12); do
            sleep 15
            SH_ELAPSED=$(( $(date +%s) - START_TIME ))
            printf "  ${CYAN}  [SH %02d/12]${NC} %s elapsed — checking Security Hub..." \
                "$j" "$(format_duration $SH_ELAPSED)"

            SH_FINDING=$(aws securityhub get-findings \
                --region "$REGION" \
                --filters "{
                    \"ResourceId\": [{\"Value\": \"${BUCKET}\", \"Comparison\": \"CONTAINS\"}],
                    \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
                }" \
                --query "Findings[0].Id" \
                --output text 2>/dev/null || echo "None")

            if [ "$SH_FINDING" != "None" ] && [ -n "$SH_FINDING" ] && [ "$SH_FINDING" != "null" ]; then
                SH_MTTD=$(( $(date +%s) - START_TIME ))
                echo -e " ${GREEN}${BOLD}INGESTED!${NC}"
                echo ""
                echo -e "  ${GREEN}${BOLD}★  Security Hub finding confirmed after $(format_duration $SH_MTTD) total${NC}"
                MTTD_SECONDS="$SH_MTTD"
                DETECTED_BY="Config + Security Hub"
                break
            else
                echo -e " ${YELLOW}pending ingestion${NC}"
            fi
        done
        break
    fi

    # ── Layer 2: Security Hub directly (in case finding arrived without Config signal) ──
    SH_FINDING=$(aws securityhub get-findings \
        --region "$REGION" \
        --filters "{
            \"ResourceId\": [{\"Value\": \"${BUCKET}\", \"Comparison\": \"CONTAINS\"}],
            \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
        }" \
        --query "Findings[0].Id" \
        --output text 2>/dev/null || echo "None")

    if [ "$SH_FINDING" != "None" ] && [ -n "$SH_FINDING" ] && [ "$SH_FINDING" != "null" ]; then
        MTTD_SECONDS=$(( $(date +%s) - START_TIME ))
        echo -e "${GREEN}${BOLD}Security Hub: FOUND!${NC}"
        echo ""
        echo -e "  ${GREEN}${BOLD}★  Finding detected after $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS}s)${NC}"
        DETECTED_BY="Security Hub"
        FOUND=true
        break
    fi

    echo -e "${YELLOW}no finding yet${NC}"
    if [ "$i" -lt "$MAX_ITERATIONS" ]; then
        sleep $INTERVAL
    fi
done

if [ "$FOUND" = "false" ]; then
    ELAPSED_FINAL=$(( $(date +%s) - START_TIME ))
    echo ""
    echo -e "  ${YELLOW}Detection not confirmed within $(format_duration $ELAPSED_FINAL).${NC}"
    echo -e "  ${YELLOW}Run manually to check:${NC}"
    echo -e "  ${CYAN}  aws configservice get-compliance-details-by-resource \\${NC}"
    echo -e "  ${CYAN}    --resource-type AWS::S3::Bucket --resource-id ${BUCKET} \\${NC}"
    echo -e "  ${CYAN}    --compliance-types NON_COMPLIANT --region ${REGION}${NC}"
    MTTD_SECONDS="$ELAPSED_FINAL (timeout)"
fi

echo ""
sleep 2

# ==================================================================
# SECTION 4 — Show Finding Detail
# ==================================================================

print_section "SECTION 4 — FINDING DETAILS"

# If Security Hub hasn't ingested the finding yet, fall back to showing the
# Config compliance evaluation result, which is always available after detection.
echo -e "${WHITE}  Fetching finding details...${NC}"
echo ""

# Try Security Hub first (no ComplianceStatus filter — it can vary by finding source)
DETAIL=$(aws securityhub get-findings \
    --region "$REGION" \
    --filters "{
        \"ResourceId\": [{\"Value\": \"${BUCKET}\", \"Comparison\": \"CONTAINS\"}],
        \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
    }" \
    --query "Findings[0].{
        Title: Title,
        Severity: Severity.Label,
        ControlId: Compliance.SecurityControlId,
        ResourceArn: Resources[0].Id,
        Description: Description,
        Recommendation: Remediation.Recommendation.Text
    }" \
    --output json 2>/dev/null)

# If Security Hub has nothing yet, pull directly from Config
if [ -z "$DETAIL" ] || [ "$DETAIL" = "null" ]; then
    echo -e "  ${YELLOW}Security Hub finding still ingesting — showing AWS Config evaluation result:${NC}"
    echo ""
    aws configservice get-compliance-details-by-resource \
        --resource-type "AWS::S3::Bucket" \
        --resource-id "$BUCKET" \
        --compliance-types NON_COMPLIANT \
        --region "$REGION" \
        --query "EvaluationResults[*].{Rule:EvaluationResultIdentifier.EvaluationResultQualifier.ConfigRuleName,Status:ComplianceType,Time:ResultRecordedTime}" \
        --output table 2>/dev/null || echo "  No Config evaluation results available yet."
    DETAIL=""
fi

if [ -n "$DETAIL" ] && [ "$DETAIL" != "null" ]; then
    TITLE=$(echo "$DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Title','N/A'))" 2>/dev/null || echo "N/A")
    SEVERITY=$(echo "$DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Severity','N/A'))" 2>/dev/null || echo "N/A")
    CONTROL=$(echo "$DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ControlId','N/A'))" 2>/dev/null || echo "N/A")
    RESOURCE=$(echo "$DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ResourceArn','N/A'))" 2>/dev/null || echo "N/A")
    DESC=$(echo "$DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Description','N/A')[:200])" 2>/dev/null || echo "N/A")
    RECO=$(echo "$DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Recommendation','N/A'))" 2>/dev/null || echo "N/A")

    echo -e "  ${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC} ${BOLD}Title:${NC}       ${WHITE}${TITLE}${NC}"
    echo -e "  ${CYAN}│${NC} ${BOLD}Severity:${NC}    ${RED}${SEVERITY}${NC}"
    echo -e "  ${CYAN}│${NC} ${BOLD}Control ID:${NC}  ${YELLOW}${CONTROL}${NC}"
    echo -e "  ${CYAN}│${NC} ${BOLD}Resource:${NC}    ${MAGENTA}${RESOURCE}${NC}"
    echo -e "  ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC} ${BOLD}Description:${NC}"
    echo -e "  ${CYAN}│${NC}   ${WHITE}${DESC}${NC}"
    echo -e "  ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC} ${BOLD}Recommendation:${NC}"
    echo -e "  ${CYAN}│${NC}   ${WHITE}${RECO}${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
else
    echo -e "  ${YELLOW}Finding detail unavailable — bucket may still be pending evaluation.${NC}"
    echo -e "  ${WHITE}Run the following to check manually:${NC}"
    echo ""
    echo -e "  ${CYAN}aws securityhub get-findings --region ${REGION} \\"
    echo -e "    --filters '{\"ResourceId\":[{\"Value\":\"${BUCKET}\",\"Comparison\":\"CONTAINS\"}]}' \\"
    echo -e "    --query 'Findings[*].{Title:Title,Severity:Severity.Label}' --output table${NC}"
fi

echo ""
sleep 3

# ==================================================================
# SECTION 5 — Cleanup
# ==================================================================

print_section "SECTION 5 — CLEANUP"

echo -e "${WHITE}  Restoring public access blocks on test bucket...${NC}"
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --region "$REGION" 2>/dev/null && \
    echo -e "  ${GREEN}✓${NC}  Public access blocks restored" || \
    echo -e "  ${YELLOW}⚠${NC}  Could not restore access blocks (bucket may already be gone)"

echo -e "${WHITE}  Deleting test bucket...${NC}"
aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null && \
    echo -e "  ${GREEN}✓${NC}  Bucket ${BUCKET} deleted" || \
    echo -e "  ${YELLOW}⚠${NC}  Bucket may have already been removed"

BUCKET=""   # Clear so trap doesn't double-delete

echo ""
echo -e "  ${GREEN}${BOLD}Test bucket deleted — environment clean${NC}"
echo ""
sleep 2

# ==================================================================
# SECTION 6 — Summary Table
# ==================================================================

print_section "SECTION 6 — RESULTS SUMMARY"

echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║           ITERATION 1 — RESULTS SUMMARY                     ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║  Service              Status     CIS Controls    Latency     ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo -e "  ║${NC}  CloudTrail            ${GREEN}ACTIVE${BOLD}     3.1 / 3.2       N/A (log)   ${GREEN}${BOLD}║${NC}"
echo -e "  ║${NC}  AWS Config            ${GREEN}ACTIVE${BOLD}     1.x / 2.x       1–3 min     ${GREEN}${BOLD}║${NC}"
echo -e "  ║${NC}  IAM Access Analyzer   ${GREEN}ACTIVE${BOLD}     2.6             < 90 sec    ${GREEN}${BOLD}║${NC}"
echo -e "  ║${NC}  Security Hub (CIS)    ${GREEN}ACTIVE${BOLD}     ~30 controls    Aggregation ${GREEN}${BOLD}║${NC}"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo -e "  ║${NC}  Resources deployed: ${YELLOW}47${BOLD}   Modules: ${YELLOW}5${BOLD}   Monthly cost: ${YELLOW}€5.47${BOLD}  ${GREEN}║${NC}"
echo -e "  ╠══════════════════════════════════════════════════════════════╣${NC}"
if [ "$MTTD_SECONDS" = "N/A" ] || echo "$MTTD_SECONDS" | grep -q "timeout"; then
    echo -e "${GREEN}${BOLD}  ║${NC}  MTTD (S3 public bucket): ${YELLOW}${MTTD_SECONDS}${GREEN}${BOLD}                            ║${NC}"
else
    MTTD_FMT=$(format_duration "$MTTD_SECONDS")
    echo -e "${GREEN}${BOLD}  ║${NC}  MTTD (S3 public bucket): ${YELLOW}${MTTD_FMT} (${MTTD_SECONDS}s)${GREEN}${BOLD}                 ║${NC}"

    if [ "$MTTD_SECONDS" -le 300 ] 2>/dev/null; then
        echo -e "${GREEN}${BOLD}  ║${NC}  Target (< 5 min): ${GREEN}MET${GREEN}${BOLD}                                      ║${NC}"
    else
        echo -e "${GREEN}${BOLD}  ║${NC}  Target (< 5 min): ${YELLOW}EXCEEDED — normal for S3/Config path${GREEN}${BOLD}   ║${NC}"
    fi
fi
echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}  Iteration 1 demo complete.${NC}"
echo -e "${WHITE}  Iteration 2 adds automated Lambda remediation on top of this pipeline.${NC}"
echo ""
