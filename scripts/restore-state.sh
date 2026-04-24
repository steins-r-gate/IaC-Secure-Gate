#!/usr/bin/env bash
# ==================================================================
# IaC Secure Gate — Terraform State Restoration Script
#
# Reconstructs terraform.tfstate by importing all existing AWS
# resources. Safe to run: only calls `terraform import` and
# read-only AWS CLI commands. Nothing in AWS is modified.
#
# USAGE:
#   cd terraform/environments/dev
#   bash ../../scripts/restore-state.sh
#
# PRE-REQUISITES:
#   - AWS CLI configured with the project's IAM credentials
#   - Terraform >= 1.5.0 installed
#   - Run from terraform/environments/dev/ directory
#
# AFTER RUNNING:
#   1. Create terraform.tfvars with real values (see end of script)
#   2. Run: terraform plan
#   3. Review the plan — DO NOT apply if any 'destroy' actions appear
# ==================================================================

set -uo pipefail

# ── Constants ─────────────────────────────────────────────────────────
readonly PROJECT="iam-secure-gate"
readonly ENV="dev"
readonly ACCOUNT="826232761554"
readonly REGION="eu-west-1"
readonly P="${PROJECT}-${ENV}"

IMPORTED=0
SKIPPED=0
FAILED=0
FAILED_RESOURCES=()

# ── Helpers ───────────────────────────────────────────────────────────

tf_import() {
  local addr="$1"
  local id="$2"

  # Skip if already in state
  if terraform state list 2>/dev/null | grep -qF "$addr"; then
    printf "  SKIP  %s\n" "$addr"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  local err
  err=$(MSYS_NO_PATHCONV=1 terraform import "$addr" "$id" 2>&1 >/dev/null)
  if [ $? -eq 0 ]; then
    printf "  OK    %s\n" "$addr"
    IMPORTED=$((IMPORTED + 1))
  else
    local short_err
    short_err=$(echo "$err" | grep -E '(Error|error|Cannot|cannot|not found|does not)' | head -1 | sed 's/^[[:space:]]*//')
    printf "  FAIL  %s  →  %s\n" "$addr" "${short_err:-check manually}"
    FAILED=$((FAILED + 1))
    FAILED_RESOURCES+=("${addr}  →  ${id}")
  fi
}

skip() {
  local reason="$1"; shift
  for addr in "$@"; do
    printf "  SKIP  %s  (%s)\n" "$addr" "$reason"
    SKIPPED=$((SKIPPED + 1))
  done
}

sns_arn() { echo "arn:aws:sns:${REGION}:${ACCOUNT}:${1}"; }

# ── Sanity checks ─────────────────────────────────────────────────────
if [ ! -f "main.tf" ]; then
  echo "ERROR: Run this script from terraform/environments/dev/"
  exit 1
fi

echo "=================================================================="
echo "IaC Secure Gate — Terraform State Restoration"
echo "Account : $ACCOUNT"
echo "Region  : $REGION"
echo "Env     : $ENV"
echo "=================================================================="

# ── Temporary tfvars (Terraform needs variable values to initialise) ──
TEMP_VARS_CREATED=""
if [ ! -f "terraform.tfvars" ]; then
  cat > terraform.tfvars << 'EOF'
# Temporary values used only for state import — replace with real values
owner_email          = "restore@example.com"
slack_bot_token      = "restore-placeholder"
slack_signing_secret = "restore-placeholder"
EOF
  TEMP_VARS_CREATED="1"
  echo ""
  echo "NOTE: No terraform.tfvars found. Using placeholder values for import."
  echo "      Create terraform.tfvars with real values before running 'terraform plan'."
fi
cleanup() {
  if [ -n "$TEMP_VARS_CREATED" ]; then
    rm -f terraform.tfvars
  fi
}
trap cleanup EXIT

# ── Step 1: Init ──────────────────────────────────────────────────────
echo ""
echo "==> terraform init"
terraform init -upgrade -no-color > /dev/null

# ── Step 2: Dynamic ID lookups ────────────────────────────────────────
echo ""
echo "==> Looking up dynamic resource IDs..."

KMS_KEY_ID=$(aws kms describe-key \
  --key-id "alias/${P}-logs" \
  --region "$REGION" \
  --query 'KeyMetadata.KeyId' \
  --output text 2>/dev/null || echo "")
echo "  KMS Key ID       : ${KMS_KEY_ID:-NOT FOUND}"

FLOW_LOG_ID=$(aws ec2 describe-flow-logs \
  --region "$REGION" \
  --filter "Name=log-group-name,Values=/aws/vpc-flow-logs/${P}-default-vpc" \
  --query 'FlowLogs[0].FlowLogId' \
  --output text 2>/dev/null || echo "")
[ "$FLOW_LOG_ID" = "None" ] && FLOW_LOG_ID=""
echo "  VPC Flow Log ID  : ${FLOW_LOG_ID:-NOT FOUND}"

API_GW_ID=$(aws apigateway get-rest-apis \
  --region "$REGION" \
  --query "items[?name=='${P}-slack-callback'].id" \
  --output text 2>/dev/null || echo "")
[ "$API_GW_ID" = "None" ] && API_GW_ID=""
echo "  API Gateway ID   : ${API_GW_ID:-NOT FOUND}"

V1_RES_ID=""
CB_RES_ID=""
API_DEPLOY_ID=""
if [ -n "$API_GW_ID" ]; then
  V1_RES_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_GW_ID" --region "$REGION" \
    --query "items[?pathPart=='v1'].id" --output text 2>/dev/null || echo "")
  CB_RES_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_GW_ID" --region "$REGION" \
    --query "items[?pathPart=='callback'].id" --output text 2>/dev/null || echo "")
  API_DEPLOY_ID=$(aws apigateway get-deployments \
    --rest-api-id "$API_GW_ID" --region "$REGION" \
    --query "items[0].id" --output text 2>/dev/null || echo "")
  echo "  /v1 resource ID  : ${V1_RES_ID:-NOT FOUND}"
  echo "  /callback res ID : ${CB_RES_ID:-NOT FOUND}"
  echo "  Deployment ID    : ${API_DEPLOY_ID:-NOT FOUND}"
fi

# Security Hub subscription ARNs
CIS_SUB_ARN=$(aws securityhub get-enabled-standards --region "$REGION" \
  --query "StandardsSubscriptions[?contains(StandardsArn,'cis-aws-foundations')].StandardsSubscriptionArn" \
  --output text 2>/dev/null || echo "")
FSBP_SUB_ARN=$(aws securityhub get-enabled-standards --region "$REGION" \
  --query "StandardsSubscriptions[?contains(StandardsArn,'foundational-security')].StandardsSubscriptionArn" \
  --output text 2>/dev/null || echo "")
SFN_ARN="arn:aws:states:${REGION}:${ACCOUNT}:stateMachine:${P}-hitl-orchestrator"

# Bucket names
CT_BUCKET="${P}-cloudtrail-${ACCOUNT}"
CFG_BUCKET="${P}-config-${ACCOUNT}"
LOG_BUCKET="${P}-access-logs-${ACCOUNT}"

echo ""
echo "=================================================================="
echo "==> Importing resources..."
echo "=================================================================="

# ── module.account_baseline ───────────────────────────────────────────
echo ""
echo "--- account_baseline ---"
tf_import "module.account_baseline.aws_iam_account_password_policy.this[0]"    "iam-account-password-policy"
tf_import "module.account_baseline.aws_s3_account_public_access_block.this[0]" "$ACCOUNT"
tf_import "module.account_baseline.aws_ebs_encryption_by_default.this[0]"      "default"
tf_import "module.account_baseline.aws_cloudwatch_log_group.vpc_flow_logs[0]"  "/aws/vpc-flow-logs/${P}-default-vpc"
tf_import "module.account_baseline.aws_iam_role.vpc_flow_logs[0]"              "${P}-vpc-flow-logs-role"
tf_import "module.account_baseline.aws_iam_role_policy.vpc_flow_logs[0]"       "${P}-vpc-flow-logs-role:${P}-vpc-flow-logs-policy"
if [ -n "$FLOW_LOG_ID" ]; then
  tf_import "module.account_baseline.aws_flow_log.default_vpc[0]" "$FLOW_LOG_ID"
else
  skip "ID not found via CLI" "module.account_baseline.aws_flow_log.default_vpc[0]"
fi

# ── module.foundation ─────────────────────────────────────────────────
echo ""
echo "--- foundation ---"
if [ -n "$KMS_KEY_ID" ]; then
  tf_import "module.foundation.aws_kms_key.logs"        "$KMS_KEY_ID"
  tf_import "module.foundation.aws_kms_alias.logs"      "alias/${P}-logs"
  tf_import "module.foundation.aws_kms_key_policy.logs" "$KMS_KEY_ID"
else
  skip "KMS key not found" "module.foundation.aws_kms_key.logs" \
       "module.foundation.aws_kms_alias.logs" "module.foundation.aws_kms_key_policy.logs"
fi

# S3: access-logs bucket (enable_bucket_logging=true in dev/main.tf)
tf_import "module.foundation.aws_s3_bucket.access_logs[0]"                                      "$LOG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_server_side_encryption_configuration.access_logs[0]" "$LOG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_public_access_block.access_logs[0]"                  "$LOG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_versioning.access_logs[0]"                           "$LOG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_ownership_controls.access_logs[0]"                   "$LOG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_lifecycle_configuration.access_logs[0]"              "$LOG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_policy.access_logs[0]"                               "$LOG_BUCKET"

# S3: CloudTrail bucket
tf_import "module.foundation.aws_s3_bucket.cloudtrail"                                      "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_versioning.cloudtrail"                           "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_server_side_encryption_configuration.cloudtrail" "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_public_access_block.cloudtrail"                  "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_ownership_controls.cloudtrail"                   "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_lifecycle_configuration.cloudtrail"              "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_logging.cloudtrail[0]"                           "$CT_BUCKET"
tf_import "module.foundation.aws_s3_bucket_policy.cloudtrail"                               "$CT_BUCKET"

# S3: Config bucket
tf_import "module.foundation.aws_s3_bucket.config"                                      "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_versioning.config"                           "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_server_side_encryption_configuration.config" "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_public_access_block.config"                  "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_ownership_controls.config"                   "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_lifecycle_configuration.config"              "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_logging.config[0]"                           "$CFG_BUCKET"
tf_import "module.foundation.aws_s3_bucket_policy.config"                               "$CFG_BUCKET"
# NOTE: aws_s3_bucket_object_lock_configuration skipped (enable_object_lock=false by default)

# ── module.cloudtrail ─────────────────────────────────────────────────
echo ""
echo "--- cloudtrail ---"
tf_import "module.cloudtrail.aws_cloudwatch_log_group.cloudtrail[0]"         "/aws/cloudtrail/${P}-trail"
tf_import "module.cloudtrail.aws_iam_role.cloudtrail_cloudwatch[0]"           "${P}-trail-cloudwatch-role"
tf_import "module.cloudtrail.aws_iam_role_policy.cloudtrail_cloudwatch[0]"    "${P}-trail-cloudwatch-role:${P}-trail-cloudwatch-policy"
# NOTE: aws_sns_topic.cloudtrail_notifications NOT imported — enable_sns_notifications=false in dev/main.tf
tf_import "module.cloudtrail.aws_cloudtrail.main"                             "${P}-trail"

# ── module.config ─────────────────────────────────────────────────────
echo ""
echo "--- config ---"
# NOTE: use_service_linked_role=true in dev/main.tf → custom IAM role NOT created
tf_import "module.config.aws_config_configuration_recorder.main"        "${P}-config-recorder"
tf_import "module.config.aws_config_delivery_channel.main"               "${P}-config-delivery"
tf_import "module.config.aws_config_configuration_recorder_status.main" "${P}-config-recorder"
# NOTE: aws_sns_topic.config NOT imported — enable_sns_notifications=false in dev/main.tf

# Config rules (8 rules via for_each)
CONFIG_RULES=(
  "root-account-mfa-enabled"
  "iam-password-policy"
  "access-keys-rotated"
  "iam-user-mfa-enabled"
  "cloudtrail-enabled"
  "cloudtrail-log-file-validation-enabled"
  "s3-bucket-public-read-prohibited"
  "s3-bucket-public-write-prohibited"
)
for RULE in "${CONFIG_RULES[@]}"; do
  tf_import "module.config.aws_config_config_rule.rules[\"${RULE}\"]" "$RULE"
done

# ── module.access_analyzer ────────────────────────────────────────────
echo ""
echo "--- access_analyzer ---"
tf_import "module.access_analyzer.aws_accessanalyzer_analyzer.account" "${P}-analyzer"
# NOTE: EventBridge rule/target and SNS topic NOT imported — enable_sns_notifications=false in dev/main.tf

# ── module.security_hub ───────────────────────────────────────────────
echo ""
echo "--- security_hub ---"
tf_import "module.security_hub.aws_securityhub_account.main" "$ACCOUNT"
# NOTE: EventBridge rule/target and SNS topic NOT imported — enable_critical_finding_notifications=false in dev/main.tf

# Standards subscriptions (ARNs looked up at runtime)
if [ -n "$CIS_SUB_ARN" ] && [ "$CIS_SUB_ARN" != "None" ]; then
  tf_import "module.security_hub.aws_securityhub_standards_subscription.cis[0]" "$CIS_SUB_ARN"
else
  skip "subscription ARN not found" "module.security_hub.aws_securityhub_standards_subscription.cis[0]"
fi
if [ -n "$FSBP_SUB_ARN" ] && [ "$FSBP_SUB_ARN" != "None" ]; then
  tf_import "module.security_hub.aws_securityhub_standards_subscription.foundational[0]" "$FSBP_SUB_ARN"
else
  skip "subscription ARN not found" "module.security_hub.aws_securityhub_standards_subscription.foundational[0]"
fi

# Product subscriptions — import ID format: "product_arn,subscription_arn"
tf_import "module.security_hub.aws_securityhub_product_subscription.config[0]" \
  "arn:aws:securityhub:${REGION}::product/aws/config,arn:aws:securityhub:${REGION}:${ACCOUNT}:product-subscription/aws/config"
tf_import "module.security_hub.aws_securityhub_product_subscription.access_analyzer[0]" \
  "arn:aws:securityhub:${REGION}::product/aws/access-analyzer,arn:aws:securityhub:${REGION}:${ACCOUNT}:product-subscription/aws/access-analyzer"
# NOTE: aws_securityhub_finding_aggregator and suppressed controls skipped
#       (ARNs not statically derivable; plan diff is additive-only)

# ── module.remediation_tracking ───────────────────────────────────────
echo ""
echo "--- remediation_tracking ---"
tf_import "module.remediation_tracking.aws_dynamodb_table.remediation_history"         "${P}-remediation-history"
tf_import "module.remediation_tracking.aws_iam_policy.dynamodb_access"                 "arn:aws:iam::${ACCOUNT}:policy/${P}-dynamodb-access"
tf_import "module.remediation_tracking.aws_cloudwatch_metric_alarm.throttled_requests" "${P}-dynamodb-throttles"
tf_import "module.remediation_tracking.aws_cloudwatch_metric_alarm.system_errors"      "${P}-dynamodb-errors"

# ── module.lambda_remediation ─────────────────────────────────────────
echo ""
echo "--- lambda_remediation ---"
# IAM role policy suffix differs per lambda type: iam→iam, s3→s3, sg→ec2
declare -A PTYPE=([iam]="iam" [s3]="s3" [sg]="ec2")

for TYPE in iam s3 sg; do
  FN="${P}-${TYPE}-remediation"
  ROLE="${FN}-role"
  PT="${PTYPE[$TYPE]}"
  SQS_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT}/${FN}-dlq"

  tf_import "module.lambda_remediation.aws_cloudwatch_log_group.${TYPE}_remediation[0]"            "/aws/lambda/${FN}"
  tf_import "module.lambda_remediation.aws_sqs_queue.${TYPE}_remediation_dlq[0]"                   "$SQS_URL"
  tf_import "module.lambda_remediation.aws_iam_role.${TYPE}_remediation[0]"                         "$ROLE"
  tf_import "module.lambda_remediation.aws_iam_role_policy.${TYPE}_remediation_logs[0]"             "${ROLE}:${FN}-logs-policy"
  tf_import "module.lambda_remediation.aws_iam_role_policy.${TYPE}_remediation_${PT}[0]"            "${ROLE}:${FN}-${PT}-policy"
  # NOTE: *_kms policy NOT imported — kms_key_arn=null in dev/main.tf (count=0)
  tf_import "module.lambda_remediation.aws_iam_role_policy.${TYPE}_remediation_dynamodb[0]"         "${ROLE}:${FN}-dynamodb-policy"
  tf_import "module.lambda_remediation.aws_iam_role_policy.${TYPE}_remediation_sns[0]"              "${ROLE}:${FN}-sns-policy"
  tf_import "module.lambda_remediation.aws_iam_role_policy.${TYPE}_remediation_dlq[0]"              "${ROLE}:${FN}-dlq-policy"
  tf_import "module.lambda_remediation.aws_lambda_function.${TYPE}_remediation[0]"                  "$FN"
  tf_import "module.lambda_remediation.aws_lambda_permission.${TYPE}_remediation_eventbridge[0]"    "${FN}/AllowEventBridgeInvoke"
done

# ── module.eventbridge_remediation ────────────────────────────────────
echo ""
echo "--- eventbridge_remediation ---"
tf_import "module.eventbridge_remediation.aws_iam_role.eventbridge_sfn[0]"             "${P}-eventbridge-sfn-role"
tf_import "module.eventbridge_remediation.aws_iam_role_policy.eventbridge_sfn_start[0]" "${P}-eventbridge-sfn-role:${P}-eventbridge-sfn-start"

declare -A EB_SUFFIX=([iam]="iam-wildcard-remediation" [s3]="s3-public-remediation" [sg]="sg-open-remediation")
declare -A EB_RES=([iam]="iam_wildcard" [s3]="s3_public" [sg]="sg_open")
declare -A EB_LT=([iam]="IAMRemediationLambda" [s3]="S3RemediationLambda" [sg]="SGRemediationLambda")
declare -A EB_ST=([iam]="IAMRemediationSFN" [s3]="S3RemediationSFN" [sg]="SGRemediationSFN")

for TYPE in iam s3 sg; do
  RULE="${P}-${EB_SUFFIX[$TYPE]}"
  RES="${EB_RES[$TYPE]}"
  tf_import "module.eventbridge_remediation.aws_cloudwatch_event_rule.${RES}[0]"          "$RULE"
  # NOTE: *_lambda target NOT imported — count=0 when enable_hitl=true (routes to SFN instead)
  tf_import "module.eventbridge_remediation.aws_cloudwatch_event_target.${RES}_sfn[0]"    "${RULE}/${EB_ST[$TYPE]}"
done

# ── module.self_improvement ───────────────────────────────────────────
echo ""
echo "--- self_improvement ---"
declare -A SNS_TOPICS=(
  [remediation_alerts]="remediation-alerts"
  [analytics_reports]="analytics-reports"
  [manual_review]="manual-review"
)
for TF_NAME in "${!SNS_TOPICS[@]}"; do
  TOPIC_NAME="${SNS_TOPICS[$TF_NAME]}"
  tf_import "module.self_improvement.aws_sns_topic.${TF_NAME}[0]"        "$(sns_arn "${P}-${TOPIC_NAME}")"
  tf_import "module.self_improvement.aws_sns_topic_policy.${TF_NAME}[0]" "$(sns_arn "${P}-${TOPIC_NAME}")"
done

ANA_FN="${P}-analytics"
ANA_ROLE="${ANA_FN}-role"
ANA_RULE="${ANA_FN}-schedule"

tf_import "module.self_improvement.aws_cloudwatch_log_group.analytics[0]"       "/aws/lambda/${ANA_FN}"
tf_import "module.self_improvement.aws_iam_role.analytics[0]"                   "$ANA_ROLE"
tf_import "module.self_improvement.aws_iam_role_policy.analytics_logs[0]"       "${ANA_ROLE}:${ANA_FN}-logs-policy"
tf_import "module.self_improvement.aws_iam_role_policy.analytics_dynamodb[0]"   "${ANA_ROLE}:${ANA_FN}-dynamodb-policy"
tf_import "module.self_improvement.aws_iam_role_policy.analytics_sns[0]"        "${ANA_ROLE}:${ANA_FN}-sns-policy"
tf_import "module.self_improvement.aws_lambda_function.analytics[0]"            "$ANA_FN"
tf_import "module.self_improvement.aws_cloudwatch_event_rule.analytics_schedule[0]"  "$ANA_RULE"
tf_import "module.self_improvement.aws_cloudwatch_event_target.analytics_lambda[0]"  "${ANA_RULE}/AnalyticsLambda"
tf_import "module.self_improvement.aws_lambda_permission.analytics_eventbridge[0]"   "${ANA_FN}/AllowEventBridgeInvoke"

# ── module.step_functions_hitl ────────────────────────────────────────
echo ""
echo "--- step_functions_hitl (enable_hitl=true) ---"
TRIAGE_FN="${P}-finding-triage"
TRIAGE_ROLE="${TRIAGE_FN}-role"
SFN_NAME="${P}-hitl-orchestrator"
SFN_ROLE="${SFN_NAME}-sfn-role"

tf_import "module.step_functions_hitl[0].aws_iam_role.sfn_execution"              "$SFN_ROLE"
tf_import "module.step_functions_hitl[0].aws_iam_role_policy.sfn_invoke_lambdas"  "${SFN_ROLE}:${SFN_NAME}-invoke-lambdas"
tf_import "module.step_functions_hitl[0].aws_iam_role_policy.sfn_logging"         "${SFN_ROLE}:${SFN_NAME}-logging"
tf_import "module.step_functions_hitl[0].aws_cloudwatch_log_group.sfn_logs"       "/aws/states/${SFN_NAME}"
tf_import "module.step_functions_hitl[0].aws_sfn_state_machine.hitl_orchestrator" "$SFN_ARN"
tf_import "module.step_functions_hitl[0].aws_cloudwatch_log_group.finding_triage" "/aws/lambda/${TRIAGE_FN}"
tf_import "module.step_functions_hitl[0].aws_iam_role.finding_triage"             "$TRIAGE_ROLE"
tf_import "module.step_functions_hitl[0].aws_iam_role_policy.finding_triage_logs"     "${TRIAGE_ROLE}:${TRIAGE_FN}-logs-policy"
tf_import "module.step_functions_hitl[0].aws_iam_role_policy.finding_triage_dynamodb" "${TRIAGE_ROLE}:${TRIAGE_FN}-dynamodb-policy"
tf_import "module.step_functions_hitl[0].aws_lambda_function.finding_triage"          "$TRIAGE_FN"

# ── module.slack_integration ──────────────────────────────────────────
echo ""
echo "--- slack_integration (enable_hitl=true) ---"
SN="${P}-slack-notifier"
SC="${P}-slack-callback"
CG="${P}-ci-gate-notifier"

# API Gateway resources (all need the REST API ID)
if [ -n "$API_GW_ID" ] && [ -n "$V1_RES_ID" ] && [ -n "$CB_RES_ID" ] && [ -n "$API_DEPLOY_ID" ]; then
  tf_import "module.slack_integration[0].aws_api_gateway_rest_api.slack_callback"         "$API_GW_ID"
  tf_import "module.slack_integration[0].aws_api_gateway_resource.v1"                     "${API_GW_ID}/${V1_RES_ID}"
  tf_import "module.slack_integration[0].aws_api_gateway_resource.callback"               "${API_GW_ID}/${CB_RES_ID}"
  tf_import "module.slack_integration[0].aws_api_gateway_method.callback_post"            "${API_GW_ID}/${CB_RES_ID}/POST"
  tf_import "module.slack_integration[0].aws_api_gateway_integration.callback_lambda"     "${API_GW_ID}/${CB_RES_ID}/POST"
  tf_import "module.slack_integration[0].aws_api_gateway_deployment.slack_callback"       "${API_GW_ID}/${API_DEPLOY_ID}"
  tf_import "module.slack_integration[0].aws_api_gateway_stage.slack_callback"            "${API_GW_ID}/${ENV}"
  tf_import "module.slack_integration[0].aws_api_gateway_method_settings.slack_callback"  "${API_GW_ID}/${ENV}/*/*"
  tf_import "module.slack_integration[0].aws_lambda_permission.api_gateway_callback"      "${SC}/AllowAPIGatewayInvoke"
else
  echo "  SKIP  module.slack_integration[0].aws_api_gateway_*  (API GW IDs not found)"
  SKIPPED=$((SKIPPED + 9))
fi

# SSM Parameters
tf_import "module.slack_integration[0].aws_ssm_parameter.slack_bot_token"      "/${PROJECT}/${ENV}/slack/bot-token"
tf_import "module.slack_integration[0].aws_ssm_parameter.slack_signing_secret" "/${PROJECT}/${ENV}/slack/signing-secret"

# Slack Notifier Lambda
tf_import "module.slack_integration[0].aws_cloudwatch_log_group.slack_notifier"      "/aws/lambda/${SN}"
tf_import "module.slack_integration[0].aws_iam_role.slack_notifier"                  "${SN}-role"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_notifier_logs"      "${SN}-role:${SN}-logs-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_notifier_ssm"       "${SN}-role:${SN}-ssm-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_notifier_dynamodb"  "${SN}-role:${SN}-dynamodb-policy"
tf_import "module.slack_integration[0].aws_lambda_function.slack_notifier"           "$SN"

# Slack Callback Lambda
tf_import "module.slack_integration[0].aws_cloudwatch_log_group.slack_callback"      "/aws/lambda/${SC}"
tf_import "module.slack_integration[0].aws_iam_role.slack_callback"                  "${SC}-role"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_callback_logs"      "${SC}-role:${SC}-logs-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_callback_ssm"       "${SC}-role:${SC}-ssm-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_callback_sfn"       "${SC}-role:${SC}-sfn-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.slack_callback_dynamodb"  "${SC}-role:${SC}-dynamodb-policy"
tf_import "module.slack_integration[0].aws_lambda_function.slack_callback"           "$SC"

# CI Gate Notifier Lambda
tf_import "module.slack_integration[0].aws_cloudwatch_log_group.ci_gate_notifier"     "/aws/lambda/${CG}"
tf_import "module.slack_integration[0].aws_iam_role.ci_gate_notifier"                 "${CG}-role"
tf_import "module.slack_integration[0].aws_iam_role_policy.ci_gate_notifier_logs"     "${CG}-role:${CG}-logs-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.ci_gate_notifier_ssm"      "${CG}-role:${CG}-ssm-policy"
tf_import "module.slack_integration[0].aws_iam_role_policy.ci_gate_notifier_dynamodb" "${CG}-role:${CG}-dynamodb-policy"
tf_import "module.slack_integration[0].aws_lambda_function.ci_gate_notifier"          "$CG"

# ── module.cis_alarms ─────────────────────────────────────────────────
echo ""
echo "--- cis_alarms ---"
# Metric filter import format: log_group_name:filter_name
CT_LOG_GROUP="/aws/cloudtrail/${P}-trail"
CIS_KEYS=(
  root_usage
  iam_policy_changes
  cloudtrail_config_changes
  console_auth_failures
  cmk_disable_delete
  security_group_changes
  nacl_changes
  network_gateway_changes
  route_table_changes
  vpc_changes
)
for KEY in "${CIS_KEYS[@]}"; do
  tf_import "module.cis_alarms.aws_cloudwatch_log_metric_filter.cis[\"${KEY}\"]" "${CT_LOG_GROUP}:${P}-cis-${KEY}"
  tf_import "module.cis_alarms.aws_cloudwatch_metric_alarm.cis[\"${KEY}\"]"      "${P}-cis-${KEY}"
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=================================================================="
echo "Import complete"
echo "  Imported : $IMPORTED"
echo "  Skipped  : $SKIPPED  (already in state or ID not found)"
echo "  Failed   : $FAILED"
if [ "${#FAILED_RESOURCES[@]}" -gt 0 ]; then
  echo ""
  echo "Failed — fix manually with: terraform import <addr> <id>"
  for r in "${FAILED_RESOURCES[@]}"; do
    echo "  $r"
  done
fi
echo ""
echo "NEXT STEPS:"
echo "  1. Create terraform/environments/dev/terraform.tfvars:"
echo "       owner_email          = \"<your-email>\""
echo "       slack_bot_token      = \"<your-bot-token>\""
echo "       slack_signing_secret = \"<your-signing-secret>\""
echo "  2. cd terraform/environments/dev && terraform plan"
echo "  3. Review: no 'destroy' or 'replace' actions should appear"
echo "  4. If plan is clean: proceed to Phase 4 implementation"
echo "=================================================================="
