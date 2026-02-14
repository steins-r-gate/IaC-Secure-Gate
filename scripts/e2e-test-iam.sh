#!/bin/bash
# ==================================================================
# IaC Secure Gate - E2E Test: IAM Wildcard Policy
# ==================================================================
# Measures MTTD and MTTR for IAM wildcard policy detection & remediation
# Usage: ./e2e-test-iam.sh [--timeout 20]
# ==================================================================

set -e

# ==================================================================
# Configuration
# ==================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
PROJECT_PREFIX="iam-secure-gate-dev"
DYNAMODB_TABLE="${PROJECT_PREFIX}-remediation-history"

TIMEOUT_MINUTES=20
POLL_INTERVAL=10

# Resource naming
TIMESTAMP=$(date +%s)
TEST_POLICY_NAME="e2e-timing-test-${TIMESTAMP}"
POLICY_ARN=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Results
MTTD_SECONDS="N/A"
MTTR_SECONDS="N/A"
DETECTION_STATUS="NOT_STARTED"
REMEDIATION_STATUS="NOT_STARTED"

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
    if [ -z "$seconds" ] || [ "$seconds" = "N/A" ]; then
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

print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_time() { echo -e "${MAGENTA}[TIME]${NC} $1"; }
print_debug() { echo -e "${YELLOW}[DEBUG]${NC} $1"; }

cleanup() {
    echo ""
    print_step "Cleaning up test resources..."

    if [ -n "$POLICY_ARN" ]; then
        # Delete policy versions first
        for version in $(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
            --query "Versions[?!IsDefaultVersion].VersionId" --output text 2>/dev/null); do
            aws iam delete-policy-version --policy-arn "${POLICY_ARN}" \
                --version-id "$version" 2>/dev/null || true
        done
        # Delete policy
        aws iam delete-policy --policy-arn "${POLICY_ARN}" 2>/dev/null || true
        print_success "IAM policy deleted"
    fi
}

trap cleanup EXIT

# ==================================================================
# Main Test
# ==================================================================

print_header "E2E TEST: IAM WILDCARD POLICY"

echo -e "Account:  ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "Region:   ${CYAN}${REGION}${NC}"
echo -e "Timeout:  ${CYAN}${TIMEOUT_MINUTES} minutes${NC}"
echo -e "Resource: ${CYAN}${TEST_POLICY_NAME}${NC}"
echo ""

# ----------------------------------------------
# Step 1: Create the violation
# ----------------------------------------------
print_step "Creating IAM policy with wildcard permissions..."
START_TIME=$(get_timestamp)

POLICY_ARN=$(aws iam create-policy \
    --policy-name "${TEST_POLICY_NAME}" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Wildcard","Effect":"Allow","Action":"*","Resource":"*"}]}' \
    --query "Policy.Arn" --output text)

print_success "Policy created: ${POLICY_ARN}"
print_time "Violation created at: $(date -u +"%H:%M:%S UTC")"
echo ""

# ----------------------------------------------
# Step 2: Wait for Security Hub detection
# ----------------------------------------------
print_step "Waiting for Security Hub detection..."
print_debug "Looking for findings with ResourceId=${POLICY_ARN}"

TIMEOUT_SECONDS=$((TIMEOUT_MINUTES * 60))
ELAPSED=0
DETECTION_TIME=""

while [ $ELAPSED -lt $TIMEOUT_SECONDS ]; do
    # Query Security Hub for findings about this policy
    FINDING=$(aws securityhub get-findings \
        --filters "{
            \"ResourceId\": [{\"Value\": \"${POLICY_ARN}\", \"Comparison\": \"EQUALS\"}],
            \"ComplianceStatus\": [{\"Value\": \"FAILED\", \"Comparison\": \"EQUALS\"}],
            \"RecordState\": [{\"Value\": \"ACTIVE\", \"Comparison\": \"EQUALS\"}]
        }" \
        --query "Findings[0].Id" --output text --region "${REGION}" 2>/dev/null || echo "None")

    if [ "$FINDING" != "None" ] && [ -n "$FINDING" ] && [ "$FINDING" != "null" ]; then
        DETECTION_TIME=$(get_timestamp)
        MTTD_SECONDS=$((DETECTION_TIME - START_TIME))
        DETECTION_STATUS="SUCCESS"
        echo ""
        print_success "Finding detected!"
        print_time "MTTD: $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS}s)"
        break
    fi

    # Progress indicator
    printf "\r  Elapsed: $(format_duration $ELAPSED) / $(format_duration $TIMEOUT_SECONDS)..."
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$DETECTION_STATUS" != "SUCCESS" ]; then
    echo ""
    print_warning "Detection timeout after ${TIMEOUT_MINUTES} minutes"
    DETECTION_STATUS="TIMEOUT"
fi

echo ""

# ----------------------------------------------
# Step 3: Wait for remediation (DynamoDB record)
# ----------------------------------------------
if [ "$DETECTION_STATUS" = "SUCCESS" ]; then
    print_step "Waiting for auto-remediation..."

    REMEDIATION_TIMEOUT=180
    ELAPSED=0

    while [ $ELAPSED -lt $REMEDIATION_TIMEOUT ]; do
        RECORD=$(aws dynamodb scan \
            --table-name "${DYNAMODB_TABLE}" \
            --filter-expression "contains(resource_arn, :pattern)" \
            --expression-attribute-values "{\":pattern\":{\"S\":\"${TEST_POLICY_NAME}\"}}" \
            --query "Items[0].finding_id.S" --output text --region "${REGION}" 2>/dev/null || echo "None")

        if [ "$RECORD" != "None" ] && [ -n "$RECORD" ] && [ "$RECORD" != "null" ]; then
            REMEDIATION_TIME=$(get_timestamp)
            MTTR_SECONDS=$((REMEDIATION_TIME - DETECTION_TIME))
            REMEDIATION_STATUS="SUCCESS"
            echo ""
            print_success "Remediation confirmed!"
            print_time "MTTR: $(format_duration $MTTR_SECONDS) (${MTTR_SECONDS}s)"
            break
        fi

        printf "\r  Waiting for DynamoDB record: ${ELAPSED}s / ${REMEDIATION_TIMEOUT}s..."
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done

    if [ "$REMEDIATION_STATUS" != "SUCCESS" ]; then
        echo ""
        print_warning "Remediation not confirmed within ${REMEDIATION_TIMEOUT}s"
        REMEDIATION_STATUS="TIMEOUT"
    fi
fi

# ----------------------------------------------
# Step 4: Verify remediation
# ----------------------------------------------
if [ "$REMEDIATION_STATUS" = "SUCCESS" ]; then
    echo ""
    print_step "Verifying policy was remediated..."

    # Check if policy has new version (remediated)
    VERSIONS=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
        --query "length(Versions)" --output text 2>/dev/null || echo "1")

    if [ "$VERSIONS" -gt 1 ]; then
        print_success "Policy has ${VERSIONS} versions (remediation created new version)"
    else
        print_warning "Policy still has only 1 version"
    fi
fi

# ==================================================================
# Results Summary
# ==================================================================

print_header "TEST RESULTS"

TOTAL_SECONDS="N/A"
if [ "$MTTD_SECONDS" != "N/A" ] && [ "$MTTR_SECONDS" != "N/A" ]; then
    TOTAL_SECONDS=$((MTTD_SECONDS + MTTR_SECONDS))
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         IAM WILDCARD POLICY - E2E TEST RESULTS            ║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Resource: ${CYAN}${TEST_POLICY_NAME}${NC}"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  ${MAGENTA}MTTD:${NC} $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS} seconds)"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  ${MAGENTA}MTTR:${NC} $(format_duration $MTTR_SECONDS) (${MTTR_SECONDS} seconds)"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  ${MAGENTA}Total:${NC} $(format_duration $TOTAL_SECONDS)"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  Detection:   ${DETECTION_STATUS}"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}  Remediation: ${REMEDIATION_STATUS}"
printf "${GREEN}║${NC}  %-58s ${GREEN}║${NC}\n" ""
echo -e "${GREEN}║${NC}                                                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Targets: MTTD < 15min, MTTR < 5min                        ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Save results
RESULTS_FILE="${RESULTS_DIR}/e2e-iam-results-$(date +%Y%m%d-%H%M%S).txt"
cat > "${RESULTS_FILE}" << EOF
IaC Secure Gate - E2E Test Results: IAM Wildcard Policy
========================================================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Account: ${ACCOUNT_ID}
Region: ${REGION}

Resource: ${TEST_POLICY_NAME}
Policy ARN: ${POLICY_ARN}

Results:
--------
MTTD (Mean Time to Detect):    $(format_duration $MTTD_SECONDS) (${MTTD_SECONDS} seconds)
MTTR (Mean Time to Remediate): $(format_duration $MTTR_SECONDS) (${MTTR_SECONDS} seconds)
Total E2E Time:                $(format_duration $TOTAL_SECONDS)

Status:
- Detection:   ${DETECTION_STATUS}
- Remediation: ${REMEDIATION_STATUS}

Target Metrics:
- MTTD Target: < 15 minutes (900 seconds)
- MTTR Target: < 5 minutes (300 seconds)
EOF

print_success "Results saved to: ${RESULTS_FILE}"
echo ""
