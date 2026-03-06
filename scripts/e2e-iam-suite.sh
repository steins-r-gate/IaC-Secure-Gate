#!/bin/bash
# ==================================================================
# IaC Secure Gate - IAM E2E Test Suite
# ==================================================================
# Tests 10 distinct IAM policy violation scenarios end-to-end:
#   Real IAM policy → Security Hub → EventBridge → Step Functions
#   → finding_triage → iam_remediation → DynamoDB audit record
#
# Paths exercised:
#   AUTO_REMEDIATE → REMEDIATED      (T1-T5, T8-T10)
#   AUTO_REMEDIATE → NO_ACTION_NEEDED (T6 - conditioned wildcard)
#   SKIP_FALSE_POSITIVE               (T7 - false positive registry)
#
# Usage: ./e2e-iam-suite.sh [--timeout 20]
# ==================================================================

set -e

# ==================================================================
# Configuration
# ==================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

export AWS_PAGER=""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
PROJECT_PREFIX="iam-secure-gate-dev"
DYNAMODB_TABLE="${PROJECT_PREFIX}-remediation-history"

TIMEOUT_MINUTES=20
POLL_INTERVAL=10
REMEDIATION_TIMEOUT=240   # seconds to wait for DynamoDB record (Phase 3)
ABSENCE_WAIT=90           # seconds to wait before checking absence (T6, T7)

TIMESTAMP=$(date +%s)
SUITE_PREFIX="e2e-suite-${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ==================================================================
# Test Definitions (indices 0-9 = T1-T10)
# ==================================================================

TEST_IDS=("T1"  "T2"             "T3"      "T4"              "T5"                 "T6"                 "T7"              "T8"             "T9"                   "T10")
TEST_LABELS=(
    "Action:\"*\""
    "Safe-first ordering"
    "Action:[\"*\"] list"
    "Mixed wildcards"
    "Two dangerous stmts"
    "Conditioned wildcard"
    "False positive"
    "Version limit"
    "Sandwich safe+*+safe"
    "Allow+Deny wildcard"
)
TEST_EXPECTED=(
    "REMEDIATED"
    "REMEDIATED"
    "REMEDIATED"
    "REMEDIATED"
    "REMEDIATED"
    "NO_ACTION_NEEDED"
    "SKIP_FALSE_POSITIVE"
    "REMEDIATED"
    "REMEDIATED"
    "REMEDIATED"
)

# Per-test state
declare -a TEST_NAMES
declare -a TEST_ARNS
declare -a TEST_DETECTED
declare -a TEST_MTTD
declare -a TEST_DETECT_TIME
declare -a TEST_ACTUAL
declare -a TEST_PASS

for i in {0..9}; do
    TEST_NAMES[$i]="${SUITE_PREFIX}-${TEST_IDS[$i]}"
    TEST_ARNS[$i]=""
    TEST_DETECTED[$i]="false"
    TEST_MTTD[$i]="N/A"
    TEST_DETECT_TIME[$i]="0"
    TEST_ACTUAL[$i]="PENDING"
    TEST_PASS[$i]="--"
done

# ==================================================================
# Parse Arguments
# ==================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT_MINUTES="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--timeout MINUTES]"
            echo "  --timeout  Detection timeout in minutes (default: 20)"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# ==================================================================
# Helper Functions
# ==================================================================

get_timestamp() { date +%s; }

format_duration() {
    local seconds=$1
    if [ -z "$seconds" ] || [ "$seconds" = "N/A" ] || [ "$seconds" = "0" ]; then
        echo "N/A"
        return
    fi
    local minutes=$((seconds / 60))
    local remaining=$((seconds % 60))
    if [ $minutes -gt 0 ]; then
        echo "${minutes}m ${remaining}s"
    else
        echo "${seconds}s"
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
}

print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_time()    { echo -e "${MAGENTA}[TIME]${NC} $1"; }

cleanup() {
    echo ""
    print_step "Cleaning up test resources..."

    # Remove T7 false positive registry entry (index 6)
    local t7_arn="${TEST_ARNS[6]}"
    if [ -n "$t7_arn" ]; then
        local fp_ts
        fp_ts=$(aws dynamodb query \
            --table-name "${DYNAMODB_TABLE}" \
            --key-condition-expression "violation_type = :vt" \
            --filter-expression "resource_arn = :arn" \
            --expression-attribute-values "{\":vt\":{\"S\":\"FALSE_POSITIVE\"},\":arn\":{\"S\":\"${t7_arn}\"}}" \
            --query "Items[0].timestamp.S" \
            --output text --region "${REGION}" 2>/dev/null || echo "None")

        if [ "$fp_ts" != "None" ] && [ -n "$fp_ts" ] && [ "$fp_ts" != "null" ]; then
            aws dynamodb delete-item \
                --table-name "${DYNAMODB_TABLE}" \
                --key "{\"violation_type\":{\"S\":\"FALSE_POSITIVE\"},\"timestamp\":{\"S\":\"${fp_ts}\"}}" \
                --region "${REGION}" 2>/dev/null || true
            print_success "T7 false positive registry entry removed"
        fi
    fi

    # Delete all 10 test policies
    for i in {0..9}; do
        local arn="${TEST_ARNS[$i]}"
        if [ -n "$arn" ]; then
            # Delete non-default versions first (handles T8's extra versions)
            for version in $(aws iam list-policy-versions --policy-arn "${arn}" \
                --query "Versions[?!IsDefaultVersion].VersionId" --output text 2>/dev/null || true); do
                aws iam delete-policy-version --policy-arn "${arn}" \
                    --version-id "$version" 2>/dev/null || true
            done
            aws iam delete-policy --policy-arn "${arn}" 2>/dev/null || true
            print_success "${TEST_IDS[$i]}: ${TEST_NAMES[$i]} deleted"
        fi
    done
}

trap cleanup EXIT

# ==================================================================
# Phase 1: Setup & Violation Creation
# ==================================================================

print_header "IAM E2E TEST SUITE — PHASE 1: SETUP"

echo -e "Account:  ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "Region:   ${CYAN}${REGION}${NC}"
echo -e "Timeout:  ${CYAN}${TIMEOUT_MINUTES} minutes${NC}"
echo -e "Prefix:   ${CYAN}${SUITE_PREFIX}${NC}"
echo ""

print_step "Creating 10 IAM test violations..."
echo ""

SUITE_START=$(get_timestamp)

# ── T1: Full wildcard — core happy path ──────────────────────────
TEST_ARNS[0]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[0]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Wildcard","Effect":"Allow","Action":"*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T1: ${TEST_NAMES[0]} (Action: \"*\")"

# ── T2: Safe statement FIRST, then dangerous (tests ordering) ────
# IAM.21 (iam:* solo) doesn't fire within 20 min in this environment.
# This redesigned T2 uses Action:"*" to trigger IAM.1, but places the
# safe statement first — confirming the Lambda finds dangerous stmts
# regardless of their position in the statement array.
TEST_ARNS[1]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[1]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"SafeFirst","Effect":"Allow","Action":"s3:GetObject","Resource":"*"},{"Sid":"DangerousLast","Effect":"Allow","Action":"*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T2: ${TEST_NAMES[1]} (Safe stmt first, then Action:\"*\")"

# ── T3: Wildcard as JSON array (tests list normalization path) ───
# Note: "*:*" is handled by iam_remediation but rejected by AWS IAM at
# creation time ("Action vendors must not contain wildcards"), so we use
# Action: ["*"] to test the array-format code path instead.
TEST_ARNS[2]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[2]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"WildcardList","Effect":"Allow","Action":["*"],"Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T3: ${TEST_NAMES[2]} (Action: [\"*\"] — array form)"

# ── T4: Mixed — dangerous + safe statements ──────────────────────
TEST_ARNS[3]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[3]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Dangerous","Effect":"Allow","Action":"*","Resource":"*"},{"Sid":"Safe","Effect":"Allow","Action":"s3:GetObject","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T4: ${TEST_NAMES[3]} (Mixed: wildcard + safe stmt)"

# ── T5: Two dangerous statements ────────────────────────────────
TEST_ARNS[4]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[4]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"WildcardAll","Effect":"Allow","Action":"*","Resource":"*"},{"Sid":"IAMAdmin","Effect":"Allow","Action":"iam:*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T5: ${TEST_NAMES[4]} (Two dangerous stmts)"

# ── T6: Conditioned wildcard — NOT a true admin grant ───────────
TEST_ARNS[5]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[5]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"ConditionedWildcard","Effect":"Allow","Action":"*","Resource":"*","Condition":{"StringEquals":{"aws:RequestedRegion":"eu-west-1"}}}]}' \
    --query "Policy.Arn" --output text)
print_success "T6: ${TEST_NAMES[5]} (Conditioned wildcard → expected NO_ACTION_NEEDED)"

# ── T7: False positive candidate — create policy first ──────────
TEST_ARNS[6]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[6]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Wildcard","Effect":"Allow","Action":"*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T7: ${TEST_NAMES[6]} (Will be pre-registered as false positive)"

# T7: Pre-register as false positive in DynamoDB
FP_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000000+00:00")
FP_TTL=$(($(date +%s) + 7776000))  # 90 days from now

aws dynamodb put-item \
    --table-name "${DYNAMODB_TABLE}" \
    --item "{
        \"violation_type\":{\"S\":\"FALSE_POSITIVE\"},
        \"timestamp\":{\"S\":\"${FP_TIMESTAMP}\"},
        \"resource_arn\":{\"S\":\"${TEST_ARNS[6]}\"},
        \"control_id\":{\"S\":\"IAM.1\"},
        \"marked_by\":{\"S\":\"e2e-suite\"},
        \"environment\":{\"S\":\"dev\"},
        \"expiration_time\":{\"N\":\"${FP_TTL}\"}
    }" \
    --region "${REGION}"
print_success "T7: False positive registered in DynamoDB"

# ── T8: Version limit — create policy then fill to IAM limit ────
TEST_ARNS[7]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[7]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Wildcard","Effect":"Allow","Action":"*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T8: ${TEST_NAMES[7]} (v1 created, adding 4 more versions...)"

# Add 4 non-default versions to reach the IAM limit of 5
for v in 2 3 4 5; do
    aws iam create-policy-version \
        --policy-arn "${TEST_ARNS[7]}" \
        --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Wildcard","Effect":"Allow","Action":"*","Resource":"*"}]}' \
        --no-set-as-default > /dev/null
done
T8_INITIAL_VERSIONS=$(aws iam list-policy-versions --policy-arn "${TEST_ARNS[7]}" \
    --query "length(Versions)" --output text)
print_success "T8: ${T8_INITIAL_VERSIONS}/5 versions created (at IAM limit — oldest must be deleted before remediation)"

# ── T9: "Sandwich" — safe + dangerous + safe (tests middle removal)
# IAM.21 for iam:*/s3:* doesn't fire within 20 min. Redesigned T9
# uses Action:"*" for detection and sandwiches it between two safe
# stmts — confirming the Lambda removes the middle stmt only.
TEST_ARNS[8]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[8]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Safe1","Effect":"Allow","Action":"s3:GetObject","Resource":"*"},{"Sid":"DangerousMiddle","Effect":"Allow","Action":"*","Resource":"*"},{"Sid":"Safe2","Effect":"Allow","Action":"ec2:DescribeInstances","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T9: ${TEST_NAMES[8]} (Sandwich: safe + Action:\"*\" + safe)"

# ── T10: Allow wildcard + Deny wildcard (Deny must NOT be removed)
TEST_ARNS[9]=$(aws iam create-policy \
    --policy-name "${TEST_NAMES[9]}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"AllowAll","Effect":"Allow","Action":"*","Resource":"*"},{"Sid":"DenyAll","Effect":"Deny","Action":"*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)
print_success "T10: ${TEST_NAMES[9]} (Allow+Deny wildcards)"

echo ""
print_time "All 10 violations created at: $(date -u +"%H:%M:%S UTC")"
echo ""

# ==================================================================
# Phase 2: Detection Loop (all 10 polled simultaneously)
# ==================================================================

print_header "IAM E2E TEST SUITE — PHASE 2: DETECTION"

print_step "Polling Security Hub for all 10 findings (up to ${TIMEOUT_MINUTES} min)..."
echo ""

TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
DETECTION_ELAPSED=0
DETECTED_COUNT=0

while [ $DETECTION_ELAPSED -lt $TIMEOUT_SECONDS ]; do
    for i in {0..9}; do
        [ "${TEST_DETECTED[$i]}" = "true" ] && continue

        FINDING=$(aws securityhub get-findings \
            --filters "{
                \"ResourceId\": [{\"Value\": \"${TEST_ARNS[$i]}\", \"Comparison\": \"EQUALS\"}],
                \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
                \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
            }" \
            --query "Findings[0].Id" --output text --region "${REGION}" 2>/dev/null || echo "None")

        if [ "$FINDING" != "None" ] && [ -n "$FINDING" ] && [ "$FINDING" != "null" ]; then
            CURR_TIME=$(get_timestamp)
            TEST_DETECTED[$i]="true"
            TEST_DETECT_TIME[$i]=$CURR_TIME
            TEST_MTTD[$i]=$((CURR_TIME - SUITE_START))
            DETECTED_COUNT=$((DETECTED_COUNT + 1))
            echo ""
            print_success "${TEST_IDS[$i]} DETECTED at $(format_duration "${TEST_MTTD[$i]}") — ${TEST_LABELS[$i]}"
        fi
    done

    [ $DETECTED_COUNT -eq 10 ] && break

    printf "\r  Elapsed: $(format_duration $DETECTION_ELAPSED) | Detected: %d/10 ..." "$DETECTED_COUNT"
    sleep $POLL_INTERVAL
    DETECTION_ELAPSED=$((DETECTION_ELAPSED + POLL_INTERVAL))
done

echo ""

if [ $DETECTED_COUNT -lt 10 ]; then
    print_warning "Detection phase ended: ${DETECTED_COUNT}/10 detected within ${TIMEOUT_MINUTES} minutes"
    for i in {0..9}; do
        if [ "${TEST_DETECTED[$i]}" = "false" ]; then
            TEST_ACTUAL[$i]="DETECTION_TIMEOUT"
            TEST_PASS[$i]="FAIL"
            print_warning "${TEST_IDS[$i]}: not detected (timeout)"
        fi
    done
else
    print_success "All 10 tests detected by Security Hub"
fi
echo ""

# ==================================================================
# Phase 3: Remediation Wait & Verification
# ==================================================================

print_header "IAM E2E TEST SUITE — PHASE 3: VERIFICATION"

# Indices for the three outcome categories
REMEDIATED_INDICES=(0 1 2 3 4 7 8 9)
NO_ACTION_IDX=5
SKIP_FP_IDX=6

# ── Poll DynamoDB for T1-T5, T8-T10 (REMEDIATED) ────────────────
print_step "Polling DynamoDB for remediation records (T1-T5, T8-T10)..."

REMEDIATION_START=$(get_timestamp)
declare -a PENDING_REMEDIATION=("${REMEDIATED_INDICES[@]}")

while true; do
    ELAPSED=$(($(get_timestamp) - REMEDIATION_START))
    [ $ELAPSED -ge $REMEDIATION_TIMEOUT ] && break

    STILL_PENDING=()
    for i in "${PENDING_REMEDIATION[@]}"; do
        # Skip tests that were never detected
        [ "${TEST_DETECTED[$i]}" = "false" ] && continue
        # Skip tests already verified
        [ "${TEST_ACTUAL[$i]}" = "REMEDIATED" ] && continue

        RECORD=$(aws dynamodb scan \
            --table-name "${DYNAMODB_TABLE}" \
            --filter-expression "contains(resource_arn, :pattern) AND remediation_status = :s" \
            --expression-attribute-values "{\":pattern\":{\"S\":\"${TEST_NAMES[$i]}\"},\":s\":{\"S\":\"SUCCESS\"}}" \
            --query "Items[0].finding_id.S" --output text --region "${REGION}" 2>/dev/null || echo "None")

        if [ "$RECORD" != "None" ] && [ -n "$RECORD" ] && [ "$RECORD" != "null" ]; then
            VERSIONS=$(aws iam list-policy-versions --policy-arn "${TEST_ARNS[$i]}" \
                --query "length(Versions)" --output text 2>/dev/null || echo "?")
            TEST_ACTUAL[$i]="REMEDIATED"
            TEST_PASS[$i]="PASS"
            print_success "${TEST_IDS[$i]}: REMEDIATED — DynamoDB SUCCESS confirmed, ${VERSIONS} policy versions"
        else
            STILL_PENDING+=("$i")
        fi
    done

    PENDING_REMEDIATION=("${STILL_PENDING[@]}")
    [ ${#PENDING_REMEDIATION[@]} -eq 0 ] && break

    printf "\r  Waiting for remediation: %ds / %ds | Pending: %d ..." \
        "$ELAPSED" "$REMEDIATION_TIMEOUT" "${#PENDING_REMEDIATION[@]}"
    sleep 5
done

echo ""

# Mark any remaining pending remediation tests as timeout
for i in "${PENDING_REMEDIATION[@]}"; do
    [ "${TEST_DETECTED[$i]}" = "false" ] && continue
    if [ "${TEST_ACTUAL[$i]}" = "PENDING" ]; then
        TEST_ACTUAL[$i]="REMEDIATION_TIMEOUT"
        TEST_PASS[$i]="FAIL"
        print_warning "${TEST_IDS[$i]}: remediation not confirmed within ${REMEDIATION_TIMEOUT}s"
    fi
done

# ── T8: Verify version count == 5 (oldest deleted, new added) ────
if [ "${TEST_ACTUAL[7]}" = "REMEDIATED" ]; then
    T8_FINAL_VERSIONS=$(aws iam list-policy-versions --policy-arn "${TEST_ARNS[7]}" \
        --query "length(Versions)" --output text 2>/dev/null || echo "?")
    if [ "$T8_FINAL_VERSIONS" = "5" ]; then
        print_success "T8: Version limit verified — ${T8_INITIAL_VERSIONS}→${T8_FINAL_VERSIONS} (oldest deleted, new default added)"
    else
        print_warning "T8: Version count is ${T8_FINAL_VERSIONS} (expected 5)"
    fi
fi

echo ""

# ── T6: NO_ACTION_NEEDED — verify absence of remediation ─────────
if [ "${TEST_DETECTED[$NO_ACTION_IDX]}" = "true" ]; then
    print_step "Verifying T6 NO_ACTION_NEEDED (conditioned wildcard)..."

    WAIT_UNTIL=$((TEST_DETECT_TIME[$NO_ACTION_IDX] + ABSENCE_WAIT))
    NOW=$(get_timestamp)
    SLEEP_REMAINING=$((WAIT_UNTIL - NOW))
    if [ $SLEEP_REMAINING -gt 0 ]; then
        printf "  Waiting %ds for pipeline to complete..." "$SLEEP_REMAINING"
        sleep $SLEEP_REMAINING
        echo ""
    fi

    T6_VERSIONS=$(aws iam list-policy-versions --policy-arn "${TEST_ARNS[$NO_ACTION_IDX]}" \
        --query "length(Versions)" --output text 2>/dev/null || echo "1")

    T6_RECORD=$(aws dynamodb scan \
        --table-name "${DYNAMODB_TABLE}" \
        --filter-expression "contains(resource_arn, :pattern) AND remediation_status = :s" \
        --expression-attribute-values "{\":pattern\":{\"S\":\"${TEST_NAMES[$NO_ACTION_IDX]}\"},\":s\":{\"S\":\"SUCCESS\"}}" \
        --query "Items[0].finding_id.S" --output text --region "${REGION}" 2>/dev/null || echo "None")

    if [ "$T6_VERSIONS" -eq 1 ] && \
       ([ "$T6_RECORD" = "None" ] || [ -z "$T6_RECORD" ] || [ "$T6_RECORD" = "null" ]); then
        TEST_ACTUAL[$NO_ACTION_IDX]="NO_ACTION_NEEDED"
        TEST_PASS[$NO_ACTION_IDX]="PASS"
        print_success "T6: NO_ACTION_NEEDED confirmed — 1 version, no DynamoDB SUCCESS record"
    else
        TEST_ACTUAL[$NO_ACTION_IDX]="REMEDIATED"
        TEST_PASS[$NO_ACTION_IDX]="FAIL"
        print_error "T6: Unexpectedly REMEDIATED (versions: ${T6_VERSIONS}, record: ${T6_RECORD})"
    fi
else
    TEST_ACTUAL[$NO_ACTION_IDX]="DETECTION_TIMEOUT"
    TEST_PASS[$NO_ACTION_IDX]="FAIL"
fi

echo ""

# ── T7: SKIP_FALSE_POSITIVE — verify remediation was skipped ─────
if [ "${TEST_DETECTED[$SKIP_FP_IDX]}" = "true" ]; then
    print_step "Verifying T7 SKIP_FALSE_POSITIVE (false positive registry)..."

    WAIT_UNTIL=$((TEST_DETECT_TIME[$SKIP_FP_IDX] + ABSENCE_WAIT))
    NOW=$(get_timestamp)
    SLEEP_REMAINING=$((WAIT_UNTIL - NOW))
    if [ $SLEEP_REMAINING -gt 0 ]; then
        printf "  Waiting %ds for pipeline to complete..." "$SLEEP_REMAINING"
        sleep $SLEEP_REMAINING
        echo ""
    fi

    T7_VERSIONS=$(aws iam list-policy-versions --policy-arn "${TEST_ARNS[$SKIP_FP_IDX]}" \
        --query "length(Versions)" --output text 2>/dev/null || echo "1")

    T7_RECORD=$(aws dynamodb scan \
        --table-name "${DYNAMODB_TABLE}" \
        --filter-expression "contains(resource_arn, :pattern) AND remediation_status = :s" \
        --expression-attribute-values "{\":pattern\":{\"S\":\"${TEST_NAMES[$SKIP_FP_IDX]}\"},\":s\":{\"S\":\"SUCCESS\"}}" \
        --query "Items[0].finding_id.S" --output text --region "${REGION}" 2>/dev/null || echo "None")

    if [ "$T7_VERSIONS" -eq 1 ] && \
       ([ "$T7_RECORD" = "None" ] || [ -z "$T7_RECORD" ] || [ "$T7_RECORD" = "null" ]); then
        TEST_ACTUAL[$SKIP_FP_IDX]="SKIP_FALSE_POSITIVE"
        TEST_PASS[$SKIP_FP_IDX]="PASS"
        print_success "T7: SKIP_FALSE_POSITIVE confirmed — 1 version, no DynamoDB SUCCESS record"
    else
        TEST_ACTUAL[$SKIP_FP_IDX]="REMEDIATED"
        TEST_PASS[$SKIP_FP_IDX]="FAIL"
        print_error "T7: Unexpectedly REMEDIATED (versions: ${T7_VERSIONS}, record: ${T7_RECORD})"
    fi
else
    TEST_ACTUAL[$SKIP_FP_IDX]="DETECTION_TIMEOUT"
    TEST_PASS[$SKIP_FP_IDX]="FAIL"
fi

echo ""

# ==================================================================
# Phase 4: Results Table
# ==================================================================

print_header "IAM E2E TEST SUITE — RESULTS"

TOTAL_SECONDS=$(($(get_timestamp) - SUITE_START))
PASS_COUNT=0
FAIL_COUNT=0
for i in {0..9}; do
    [ "${TEST_PASS[$i]}" = "PASS" ] && PASS_COUNT=$((PASS_COUNT + 1))
    [ "${TEST_PASS[$i]}" = "FAIL" ] && FAIL_COUNT=$((FAIL_COUNT + 1))
done

echo -e "${GREEN}╔════╦══════════════════════╦═════════════════════╦═════════════════════╦════════╦═════════╗${NC}"
printf "${GREEN}║${NC} %-2s ${GREEN}║${NC} %-20s ${GREEN}║${NC} %-19s ${GREEN}║${NC} %-19s ${GREEN}║${NC} %-6s ${GREEN}║${NC} %-7s ${GREEN}║${NC}\n" \
    "#" "Violation" "Expected" "Actual" "MTTD" "RESULT"
echo -e "${GREEN}╠════╬══════════════════════╬═════════════════════╬═════════════════════╬════════╬═════════╣${NC}"

for i in {0..9}; do
    TID="${TEST_IDS[$i]}"
    LABEL="${TEST_LABELS[$i]}"
    EXPECTED="${TEST_EXPECTED[$i]}"
    ACTUAL="${TEST_ACTUAL[$i]}"
    MTTD_FMT=$(format_duration "${TEST_MTTD[$i]}")
    RESULT="${TEST_PASS[$i]}"

    if [ "$RESULT" = "PASS" ]; then
        RC="${GREEN}"
    else
        RC="${RED}"
    fi

    printf "${GREEN}║${NC} %-2s ${GREEN}║${NC} %-20s ${GREEN}║${NC} %-19s ${GREEN}║${NC} %-19s ${GREEN}║${NC} %-6s ${GREEN}║${NC} ${RC}%-7s${NC} ${GREEN}║${NC}\n" \
        "$TID" "$LABEL" "$EXPECTED" "$ACTUAL" "$MTTD_FMT" "$RESULT"
done

echo -e "${GREEN}╠════╩══════════════════════╩═════════════════════╩═════════════════════╩════════╩═════════╣${NC}"
printf "${GREEN}║${NC} %-87s${GREEN}║${NC}\n" " Total: $(format_duration $TOTAL_SECONDS)  |  PASS: ${PASS_COUNT}/10  |  FAIL: ${FAIL_COUNT}/10"
echo -e "${GREEN}╚═════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ==================================================================
# Save Results
# ==================================================================

RESULTS_FILE="${RESULTS_DIR}/e2e-iam-suite-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "IaC Secure Gate - IAM E2E Suite Results"
    echo "========================================"
    echo "Date:          $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "Account:       ${ACCOUNT_ID}"
    echo "Region:        ${REGION}"
    echo "Suite Prefix:  ${SUITE_PREFIX}"
    echo "Total Runtime: $(format_duration $TOTAL_SECONDS)"
    echo "Result:        ${PASS_COUNT}/10 PASS, ${FAIL_COUNT}/10 FAIL"
    echo ""
    printf "%-4s  %-22s  %-21s  %-21s  %-10s  %-6s\n" \
        "Test" "Violation" "Expected" "Actual" "MTTD" "Result"
    printf "%-4s  %-22s  %-21s  %-21s  %-10s  %-6s\n" \
        "----" "----------------------" "---------------------" "---------------------" "----------" "------"
    for i in {0..9}; do
        printf "%-4s  %-22s  %-21s  %-21s  %-10s  %-6s\n" \
            "${TEST_IDS[$i]}" \
            "${TEST_LABELS[$i]}" \
            "${TEST_EXPECTED[$i]}" \
            "${TEST_ACTUAL[$i]}" \
            "$(format_duration "${TEST_MTTD[$i]}")" \
            "${TEST_PASS[$i]}"
    done
} > "${RESULTS_FILE}"

print_success "Results saved to: ${RESULTS_FILE}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    print_success "All 10 tests PASSED"
else
    print_error "${FAIL_COUNT} test(s) FAILED"
    exit 1
fi
