#!/bin/bash
# ==================================================================
# IaC Secure Gate - End-to-End Timing Test (All Scenarios)
# ==================================================================
#
# Purpose: Measure real-world MTTD and MTTR for all 3 remediation types
#          through the full EventBridge flow
#
# Scenarios:
#   1. IAM Wildcard Policy
#   2. S3 Public Bucket
#   3. Security Group Open Access
#
# Usage: ./e2e-timing-test.sh [--timeout 20] [--iam-only] [--s3-only] [--sg-only]
#
# Author: IaC Secure Gate Team
# Version: 2.0.0
# ==================================================================

set -e

# ==================================================================
# Configuration
# ==================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/.temp"
mkdir -p "${TEMP_DIR}"

to_windows_path() {
    local path="$1"
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "$path" | sed 's|^/\([a-zA-Z]\)/|\1:/|'
    else
        echo "$path"
    fi
}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="eu-west-1"
PROJECT_PREFIX="iam-secure-gate-dev"
DYNAMODB_TABLE="${PROJECT_PREFIX}-remediation-history"

TIMEOUT_MINUTES=20
POLL_INTERVAL=10
REMEDIATION_TIMEOUT=120

# Test flags
TEST_IAM=true
TEST_S3=true
TEST_SG=true

# Results storage
declare -A MTTD_RESULTS
declare -A MTTR_RESULTS
declare -A TOTAL_RESULTS
declare -A STATUS_RESULTS

# Resource names
TIMESTAMP=$(date +%s)
TEST_POLICY_NAME="e2e-test-policy-${TIMESTAMP}"
TEST_BUCKET_NAME="e2e-test-bucket-${ACCOUNT_ID}-${TIMESTAMP}"
TEST_SG_NAME="e2e-test-sg-${TIMESTAMP}"
TEST_SG_ID=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ==================================================================
# Parse Arguments
# ==================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT_MINUTES="$2"
            shift 2
            ;;
        --iam-only)
            TEST_S3=false
            TEST_SG=false
            shift
            ;;
        --s3-only)
            TEST_IAM=false
            TEST_SG=false
            shift
            ;;
        --sg-only)
            TEST_IAM=false
            TEST_S3=false
            shift
            ;;
        --help)
            echo "Usage: $0 [--timeout MINUTES] [--iam-only] [--s3-only] [--sg-only]"
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
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_time() { echo -e "${MAGENTA}[TIME]${NC} $1"; }

cleanup_resources() {
    print_header "CLEANUP"

    # IAM Policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" 2>/dev/null; then
        print_step "Deleting IAM policy..."
        for version in $(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" \
            --query "Versions[?!IsDefaultVersion].VersionId" --output text 2>/dev/null); do
            aws iam delete-policy-version --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" \
                --version-id "$version" 2>/dev/null || true
        done
        aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${TEST_POLICY_NAME}" 2>/dev/null || true
        print_success "IAM policy deleted"
    fi

    # S3 Bucket
    if aws s3api head-bucket --bucket "${TEST_BUCKET_NAME}" 2>/dev/null; then
        print_step "Deleting S3 bucket..."
        aws s3 rb "s3://${TEST_BUCKET_NAME}" --force 2>/dev/null || true
        print_success "S3 bucket deleted"
    fi

    # Security Group
    if [ -n "$TEST_SG_ID" ]; then
        print_step "Deleting Security Group..."
        aws ec2 delete-security-group --group-id "$TEST_SG_ID" --region "${REGION}" 2>/dev/null || true
        print_success "Security Group deleted"
    fi

    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    print_success "Cleanup complete"
}

trap cleanup_resources EXIT

# ==================================================================
# Test Functions
# ==================================================================

wait_for_detection() {
    local resource_filter="$1"
    local timeout_seconds=$((TIMEOUT_MINUTES * 60))
    local elapsed=0

    while [ $elapsed -lt $timeout_seconds ]; do
        FINDING=$(aws securityhub get-findings \
            --filters "$resource_filter" \
            --query "Findings[0]" --output json --region "${REGION}" 2>/dev/null || echo "null")

        if [ "$FINDING" != "null" ] && [ -n "$FINDING" ] && [ "$FINDING" != "{}" ]; then
            echo "DETECTED"
            return 0
        fi

        echo -ne "  Waiting: $(format_duration $elapsed)...\r"
        sleep $POLL_INTERVAL
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    echo "TIMEOUT"
    return 1
}

wait_for_remediation() {
    local resource_pattern="$1"
    local elapsed=0

    while [ $elapsed -lt $REMEDIATION_TIMEOUT ]; do
        RECORD=$(aws dynamodb scan --table-name "${DYNAMODB_TABLE}" \
            --filter-expression "contains(resource_arn, :pattern)" \
            --expression-attribute-values "{\":pattern\":{\"S\":\"${resource_pattern}\"}}" \
            --query "Items[0]" --output json --region "${REGION}" 2>/dev/null || echo "null")

        if [ "$RECORD" != "null" ] && [ -n "$RECORD" ] && [ "$RECORD" != "{}" ]; then
            echo "REMEDIATED"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo "TIMEOUT"
    return 1
}

# ==================================================================
# TEST 1: IAM Wildcard Policy
# ==================================================================

test_iam() {
    print_header "TEST 1: IAM WILDCARD POLICY"

    print_step "Creating IAM policy with wildcard permissions..."
    local start_time=$(get_timestamp)

    POLICY_ARN=$(aws iam create-policy \
        --policy-name "${TEST_POLICY_NAME}" \
        --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"Wildcard","Effect":"Allow","Action":"*","Resource":"*"}]}' \
        --query "Policy.Arn" --output text)

    print_success "Policy created: ${POLICY_ARN}"
    print_time "Violation created at: $(date -u +%H:%M:%S)"

    # Wait for detection
    print_step "Waiting for Security Hub detection..."
    local filter="{\"ResourceId\":[{\"Value\":\"${POLICY_ARN}\",\"Comparison\":\"EQUALS\"}],\"Compliance\":{\"Status\":[{\"Value\":\"FAILED\",\"Comparison\":\"EQUALS\"}]},\"RecordState\":[{\"Value\":\"ACTIVE\",\"Comparison\":\"EQUALS\"}]}"

    if result=$(wait_for_detection "$filter"); then
        local detection_time=$(get_timestamp)
        local mttd=$((detection_time - start_time))
        print_success "Detected! MTTD: $(format_duration $mttd)"

        # Wait for remediation
        print_step "Waiting for auto-remediation..."
        if wait_for_remediation "${TEST_POLICY_NAME}" >/dev/null; then
            local remediation_time=$(get_timestamp)
            local mttr=$((remediation_time - detection_time))
            local total=$((remediation_time - start_time))

            print_success "Remediated! MTTR: $(format_duration $mttr)"

            MTTD_RESULTS["IAM"]=$mttd
            MTTR_RESULTS["IAM"]=$mttr
            TOTAL_RESULTS["IAM"]=$total
            STATUS_RESULTS["IAM"]="SUCCESS"
        else
            print_warning "Remediation timeout"
            MTTD_RESULTS["IAM"]=$mttd
            MTTR_RESULTS["IAM"]="N/A"
            TOTAL_RESULTS["IAM"]="N/A"
            STATUS_RESULTS["IAM"]="PARTIAL"
        fi
    else
        print_warning "Detection timeout"
        MTTD_RESULTS["IAM"]="N/A"
        MTTR_RESULTS["IAM"]="N/A"
        TOTAL_RESULTS["IAM"]="N/A"
        STATUS_RESULTS["IAM"]="TIMEOUT"
    fi
}

# ==================================================================
# TEST 2: S3 Public Bucket
# ==================================================================

test_s3() {
    print_header "TEST 2: S3 PUBLIC BUCKET"

    print_step "Creating S3 bucket with public access disabled..."
    local start_time=$(get_timestamp)

    aws s3api create-bucket --bucket "${TEST_BUCKET_NAME}" --region "${REGION}" \
        --create-bucket-configuration LocationConstraint="${REGION}" >/dev/null

    aws s3api put-public-access-block --bucket "${TEST_BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

    print_success "Bucket created: ${TEST_BUCKET_NAME}"
    print_time "Violation created at: $(date -u +%H:%M:%S)"

    # Wait for detection
    print_step "Waiting for Security Hub detection..."
    local filter="{\"ResourceId\":[{\"Value\":\"arn:aws:s3:::${TEST_BUCKET_NAME}\",\"Comparison\":\"EQUALS\"}],\"Compliance\":{\"Status\":[{\"Value\":\"FAILED\",\"Comparison\":\"EQUALS\"}]},\"RecordState\":[{\"Value\":\"ACTIVE\",\"Comparison\":\"EQUALS\"}]}"

    if result=$(wait_for_detection "$filter"); then
        local detection_time=$(get_timestamp)
        local mttd=$((detection_time - start_time))
        print_success "Detected! MTTD: $(format_duration $mttd)"

        # Wait for remediation
        print_step "Waiting for auto-remediation..."
        if wait_for_remediation "${TEST_BUCKET_NAME}" >/dev/null; then
            local remediation_time=$(get_timestamp)
            local mttr=$((remediation_time - detection_time))
            local total=$((remediation_time - start_time))

            print_success "Remediated! MTTR: $(format_duration $mttr)"

            MTTD_RESULTS["S3"]=$mttd
            MTTR_RESULTS["S3"]=$mttr
            TOTAL_RESULTS["S3"]=$total
            STATUS_RESULTS["S3"]="SUCCESS"
        else
            print_warning "Remediation timeout"
            MTTD_RESULTS["S3"]=$mttd
            MTTR_RESULTS["S3"]="N/A"
            TOTAL_RESULTS["S3"]="N/A"
            STATUS_RESULTS["S3"]="PARTIAL"
        fi
    else
        print_warning "Detection timeout"
        MTTD_RESULTS["S3"]="N/A"
        MTTR_RESULTS["S3"]="N/A"
        TOTAL_RESULTS["S3"]="N/A"
        STATUS_RESULTS["S3"]="TIMEOUT"
    fi
}

# ==================================================================
# TEST 3: Security Group Open Access
# ==================================================================

test_sg() {
    print_header "TEST 3: SECURITY GROUP OPEN ACCESS"

    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text --region "${REGION}")

    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        print_warning "No default VPC found, skipping Security Group test"
        STATUS_RESULTS["SG"]="SKIPPED"
        return
    fi

    print_step "Creating Security Group with open SSH access..."
    local start_time=$(get_timestamp)

    TEST_SG_ID=$(aws ec2 create-security-group \
        --group-name "${TEST_SG_NAME}" \
        --description "E2E test - open SSH" \
        --vpc-id "${VPC_ID}" \
        --query "GroupId" --output text --region "${REGION}")

    aws ec2 authorize-security-group-ingress \
        --group-id "${TEST_SG_ID}" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 \
        --region "${REGION}" >/dev/null

    print_success "Security Group created: ${TEST_SG_ID}"
    print_time "Violation created at: $(date -u +%H:%M:%S)"

    # Wait for detection
    print_step "Waiting for Security Hub detection..."
    local filter="{\"ResourceId\":[{\"Value\":\"${TEST_SG_ID}\",\"Comparison\":\"EQUALS\"}],\"Compliance\":{\"Status\":[{\"Value\":\"FAILED\",\"Comparison\":\"EQUALS\"}]},\"RecordState\":[{\"Value\":\"ACTIVE\",\"Comparison\":\"EQUALS\"}]}"

    if result=$(wait_for_detection "$filter"); then
        local detection_time=$(get_timestamp)
        local mttd=$((detection_time - start_time))
        print_success "Detected! MTTD: $(format_duration $mttd)"

        # Wait for remediation
        print_step "Waiting for auto-remediation..."
        if wait_for_remediation "${TEST_SG_ID}" >/dev/null; then
            local remediation_time=$(get_timestamp)
            local mttr=$((remediation_time - detection_time))
            local total=$((remediation_time - start_time))

            print_success "Remediated! MTTR: $(format_duration $mttr)"

            MTTD_RESULTS["SG"]=$mttd
            MTTR_RESULTS["SG"]=$mttr
            TOTAL_RESULTS["SG"]=$total
            STATUS_RESULTS["SG"]="SUCCESS"
        else
            print_warning "Remediation timeout"
            MTTD_RESULTS["SG"]=$mttd
            MTTR_RESULTS["SG"]="N/A"
            TOTAL_RESULTS["SG"]="N/A"
            STATUS_RESULTS["SG"]="PARTIAL"
        fi
    else
        print_warning "Detection timeout"
        MTTD_RESULTS["SG"]="N/A"
        MTTR_RESULTS["SG"]="N/A"
        TOTAL_RESULTS["SG"]="N/A"
        STATUS_RESULTS["SG"]="TIMEOUT"
    fi
}

# ==================================================================
# Calculate Averages
# ==================================================================

calculate_averages() {
    local mttd_sum=0
    local mttd_count=0
    local mttr_sum=0
    local mttr_count=0

    for key in "${!MTTD_RESULTS[@]}"; do
        if [ "${MTTD_RESULTS[$key]}" != "N/A" ]; then
            mttd_sum=$((mttd_sum + MTTD_RESULTS[$key]))
            mttd_count=$((mttd_count + 1))
        fi
    done

    for key in "${!MTTR_RESULTS[@]}"; do
        if [ "${MTTR_RESULTS[$key]}" != "N/A" ]; then
            mttr_sum=$((mttr_sum + MTTR_RESULTS[$key]))
            mttr_count=$((mttr_count + 1))
        fi
    done

    if [ $mttd_count -gt 0 ]; then
        AVG_MTTD=$((mttd_sum / mttd_count))
    else
        AVG_MTTD="N/A"
    fi

    if [ $mttr_count -gt 0 ]; then
        AVG_MTTR=$((mttr_sum / mttr_count))
    else
        AVG_MTTR="N/A"
    fi
}

# ==================================================================
# Main
# ==================================================================

print_header "IaC SECURE GATE - E2E TIMING TEST (ALL SCENARIOS)"

echo -e "Account ID:      ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "Region:          ${CYAN}${REGION}${NC}"
echo -e "Timeout:         ${CYAN}${TIMEOUT_MINUTES} minutes per test${NC}"
echo ""
echo -e "${YELLOW}NOTE: This test runs all scenarios sequentially.${NC}"
echo -e "${YELLOW}      Total time may be 15-45 minutes. Please be patient.${NC}"
echo ""

# Run tests
[ "$TEST_IAM" = true ] && test_iam
[ "$TEST_S3" = true ] && test_s3
[ "$TEST_SG" = true ] && test_sg

# Calculate averages
calculate_averages

# ==================================================================
# Results Summary
# ==================================================================

print_header "FINAL RESULTS SUMMARY"

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              IaC SECURE GATE - E2E TIMING RESULTS                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}INDIVIDUAL RESULTS:${NC}                                                ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ┌────────────────┬──────────────┬──────────────┬──────────────┐    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  │ Scenario       │ MTTD         │ MTTR         │ Status       │    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ├────────────────┼──────────────┼──────────────┼──────────────┤    ${GREEN}║${NC}"

for scenario in IAM S3 SG; do
    mttd_val="${MTTD_RESULTS[$scenario]:-N/A}"
    mttr_val="${MTTR_RESULTS[$scenario]:-N/A}"
    status_val="${STATUS_RESULTS[$scenario]:-N/A}"

    mttd_fmt=$(format_duration "$mttd_val")
    mttr_fmt=$(format_duration "$mttr_val")

    printf "${GREEN}║${NC}  │ %-14s │ %-12s │ %-12s │ %-12s │    ${GREEN}║${NC}\n" \
        "$scenario" "$mttd_fmt" "$mttr_fmt" "$status_val"
done

echo -e "${GREEN}║${NC}  └────────────────┴──────────────┴──────────────┴──────────────┘    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}AVERAGES:${NC}                                                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ┌─────────────────────────────────────────────────────────────┐    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  │  ${MAGENTA}Average MTTD:${NC}  ${YELLOW}$(format_duration "$AVG_MTTD")${NC}                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  │  ${MAGENTA}Average MTTR:${NC}  ${YELLOW}$(format_duration "$AVG_MTTR")${NC}                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  └─────────────────────────────────────────────────────────────┘    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}TARGET METRICS:${NC}                                                    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}    - MTTD Target: < 15 minutes    $([ "$AVG_MTTD" != "N/A" ] && [ "$AVG_MTTD" -lt 900 ] && echo "✅ PASS" || echo "⏳")                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}    - MTTR Target: < 5 minutes     $([ "$AVG_MTTR" != "N/A" ] && [ "$AVG_MTTR" -lt 300 ] && echo "✅ PASS" || echo "⏳")                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Save results to file
RESULTS_FILE="${SCRIPT_DIR}/e2e-full-results-$(date +%Y%m%d-%H%M%S).txt"
cat > "${RESULTS_FILE}" << EOF
IaC Secure Gate - E2E Full Timing Test Results
==============================================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Account: ${ACCOUNT_ID}
Region: ${REGION}

Individual Results:
-------------------
IAM Wildcard Policy:
  - MTTD: $(format_duration "${MTTD_RESULTS[IAM]:-N/A}") (${MTTD_RESULTS[IAM]:-N/A} seconds)
  - MTTR: $(format_duration "${MTTR_RESULTS[IAM]:-N/A}") (${MTTR_RESULTS[IAM]:-N/A} seconds)
  - Status: ${STATUS_RESULTS[IAM]:-N/A}

S3 Public Bucket:
  - MTTD: $(format_duration "${MTTD_RESULTS[S3]:-N/A}") (${MTTD_RESULTS[S3]:-N/A} seconds)
  - MTTR: $(format_duration "${MTTR_RESULTS[S3]:-N/A}") (${MTTR_RESULTS[S3]:-N/A} seconds)
  - Status: ${STATUS_RESULTS[S3]:-N/A}

Security Group:
  - MTTD: $(format_duration "${MTTD_RESULTS[SG]:-N/A}") (${MTTD_RESULTS[SG]:-N/A} seconds)
  - MTTR: $(format_duration "${MTTR_RESULTS[SG]:-N/A}") (${MTTR_RESULTS[SG]:-N/A} seconds)
  - Status: ${STATUS_RESULTS[SG]:-N/A}

Averages:
---------
Average MTTD: $(format_duration "$AVG_MTTD") (${AVG_MTTD} seconds)
Average MTTR: $(format_duration "$AVG_MTTR") (${AVG_MTTR} seconds)

Target Metrics:
- MTTD Target: < 15 minutes (900 seconds)
- MTTR Target: < 5 minutes (300 seconds)
EOF

print_success "Results saved to: ${RESULTS_FILE}"
echo ""
