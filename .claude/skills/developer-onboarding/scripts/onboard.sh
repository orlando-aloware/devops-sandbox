#!/bin/bash
# =============================================================
# Developer Onboarding Script
# Provisions Jenkins + AWS Dev + AWS Staging access for a new dev
#
# Usage:
#   ./onboard.sh <email> [username]
#
# Required env vars (pre-set in shell):
#   JENKINS_USER        - Admin Jenkins username
#   JENKINS_TOKEN_NAME  - Name of the API token (informational)
#   JENKINS_TOKEN       - Jenkins API token value
#
# AWS profiles expected in ~/.aws/credentials:
#   [alwr-dev]  – account 333629833033  (dev)
#   [alwr-stg]  – account 225989345843  (staging)
# =============================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
success() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
die()     { echo -e "${RED}[ERROR]${NC}   $*" >&2; exit 1; }

# ── Args & Validation ─────────────────────────────────────────
EMAIL="${1:-}"
[[ -z "$EMAIL" ]] && die "Usage: $0 <email> [username]"

# Validate looks like an email
[[ "$EMAIL" == *@* ]] || die "Invalid email: $EMAIL"

LOCAL="${EMAIL%%@*}"     # everything before @
DOMAIN="${EMAIL##*@}"    # everything after @

# USERNAME: first name = first segment before . or _  (or override via arg 2)
FIRST_PART="${LOCAL%%.*}"   # strip suffix after first dot
FIRST_PART="${FIRST_PART%%_*}"  # strip suffix after first underscore
USERNAME="${2:-${FIRST_PART}}"
USERNAME="${USERNAME,,}"   # lowercase

# AWS usernames
AWS_DEV_USER="${LOCAL}+dev@${DOMAIN}"
AWS_STG_USER="${LOCAL}+staging@${DOMAIN}"

# Jenkins
JENKINS_URL="${JENKINS_URL:-https://jenkins.aloware.com}"

# Required env vars
: "${JENKINS_USER:?JENKINS_USER env var must be set}"
: "${JENKINS_TOKEN:?JENKINS_TOKEN env var must be set}"
: "${JENKINS_TOKEN_NAME:?JENKINS_TOKEN_NAME env var must be set (token name used for $JENKINS_USER)}"
: "${JENKINS_PASSWORD:?JENKINS_PASSWORD env var must be set}"

echo ""
echo -e "${BOLD}=== Developer Onboarding ===${NC}"
echo -e "  Email (input):       ${EMAIL}"
echo -e "  Jenkins username:    ${USERNAME}"
echo -e "  AWS Dev user:        ${AWS_DEV_USER}"
echo -e "  AWS Staging user:    ${AWS_STG_USER}"
echo ""
read -r -p "Proceed? [y/N] " confirm
[[ "${confirm,,}" == "y" ]] || { warn "Aborted."; exit 0; }
echo ""

AUTH="${JENKINS_USER}:${JENKINS_TOKEN}"

# ── Helper: CSRF crumb ────────────────────────────────────────
get_crumb_header() {
  local crumb_json
  crumb_json=$(curl -sf -u "$AUTH" "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null || echo "")
  if [[ -z "$crumb_json" ]]; then
    echo ""
    return
  fi
  local field val
  field=$(echo "$crumb_json" | jq -r '.crumbRequestField // empty')
  val=$(echo "$crumb_json"   | jq -r '.crumb            // empty')
  [[ -n "$field" && -n "$val" ]] && echo "${field}: ${val}" || echo ""
}

# ═══════════════════════════════════════════════════════════════
# 1. JENKINS
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}── Jenkins ────────────────────────────────────────────────${NC}"

CRUMB_HEADER=$(get_crumb_header)
CRUMB_ARGS=()
[[ -n "$CRUMB_HEADER" ]] && CRUMB_ARGS=(-H "$CRUMB_HEADER")

# Use shared onboarding password from env
TEMP_PASS="${JENKINS_PASSWORD}"

# Create user via Groovy script console
GROOVY=$(cat <<GROOVY
def realm = jenkins.model.Jenkins.instance.securityRealm
try {
  realm.createAccount('${USERNAME}', '${TEMP_PASS}')
  println "CREATED"
} catch (Exception e) {
  if (e.message?.contains("already exists") || e.message?.contains("already taken")) {
    println "EXISTS"
  } else {
    throw e
  }
}
GROOVY
)

info "Creating Jenkins user '${USERNAME}'..."
SCRIPT_OUT=$(curl -sf -X POST -u "$AUTH" "${CRUMB_ARGS[@]}" \
  --data-urlencode "script=${GROOVY}" \
  "${JENKINS_URL}/scriptText" 2>&1 || true)

if echo "$SCRIPT_OUT" | grep -q "EXISTS"; then
  warn "Jenkins user '${USERNAME}' already exists – skipping creation."
elif echo "$SCRIPT_OUT" | grep -q "CREATED"; then
  success "Jenkins user '${USERNAME}' created."
else
  # Non-fatal: log and continue
  warn "Script console response: ${SCRIPT_OUT}"
fi

# Assign 'engineer' global role (Role Strategy plugin)
info "Assigning role 'engineer' to '${USERNAME}'..."
ROLE_HTTP=$(curl -so /dev/null -w "%{http_code}" -X POST -u "$AUTH" "${CRUMB_ARGS[@]}" \
  "${JENKINS_URL}/role-strategy/strategy/assignRole" \
  -d "type=globalRoles&roleName=engineer&sid=${USERNAME}" 2>&1 || echo "000")

if [[ "$ROLE_HTTP" == "200" || "$ROLE_HTTP" == "302" ]]; then
  success "Role 'engineer' assigned to '${USERNAME}'."
else
  warn "Role assignment returned HTTP ${ROLE_HTTP} – verify manually at ${JENKINS_URL}/role-strategy/"
fi

# ═══════════════════════════════════════════════════════════════
# 2. AWS DEV  (account 333629833033, profile alwr-dev)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}── AWS Dev (333629833033) ─────────────────────────────────${NC}"

info "Creating IAM user '${AWS_DEV_USER}'..."
if aws --profile alwr-dev iam create-user --user-name "${AWS_DEV_USER}" \
    --output text --query 'User.UserName' > /dev/null 2>&1; then
  success "IAM user '${AWS_DEV_USER}' created."
else
  EX=$?
  ERR=$(aws --profile alwr-dev iam get-user --user-name "${AWS_DEV_USER}" \
         --output text --query 'User.UserName' 2>/dev/null || true)
  if [[ -n "$ERR" ]]; then
    warn "IAM user '${AWS_DEV_USER}' already exists – skipping creation."
  else
    die "Failed to create IAM user '${AWS_DEV_USER}' (exit ${EX})."
  fi
fi

info "Adding '${AWS_DEV_USER}' to group KubernetesDevelopers..."
aws --profile alwr-dev iam add-user-to-group \
  --user-name "${AWS_DEV_USER}" --group-name KubernetesDevelopers
success "Added to KubernetesDevelopers."

info "Creating programmatic access key for '${AWS_DEV_USER}'..."
DEV_KEY_JSON=$(aws --profile alwr-dev iam create-access-key \
  --user-name "${AWS_DEV_USER}" \
  --output json --query 'AccessKey.{KeyId:AccessKeyId,Secret:SecretAccessKey}')
DEV_KEY_ID=$(echo "$DEV_KEY_JSON"    | jq -r '.KeyId')
DEV_KEY_SECRET=$(echo "$DEV_KEY_JSON" | jq -r '.Secret')
success "Access key created for dev."

# ═══════════════════════════════════════════════════════════════
# 3. AWS STAGING  (account 225989345843, profile alwr-stg)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}── AWS Staging (225989345843) ─────────────────────────────${NC}"

info "Creating IAM user '${AWS_STG_USER}'..."
if aws --profile alwr-stg iam create-user --user-name "${AWS_STG_USER}" \
    --output text --query 'User.UserName' > /dev/null 2>&1; then
  success "IAM user '${AWS_STG_USER}' created."
else
  ERR=$(aws --profile alwr-stg iam get-user --user-name "${AWS_STG_USER}" \
         --output text --query 'User.UserName' 2>/dev/null || true)
  if [[ -n "$ERR" ]]; then
    warn "IAM user '${AWS_STG_USER}' already exists – skipping creation."
  else
    die "Failed to create IAM user '${AWS_STG_USER}'."
  fi
fi

info "Adding '${AWS_STG_USER}' to group KubernetesDevelopers..."
aws --profile alwr-stg iam add-user-to-group \
  --user-name "${AWS_STG_USER}" --group-name KubernetesDevelopers
success "Added to KubernetesDevelopers."

info "Adding '${AWS_STG_USER}' to group liveforge..."
aws --profile alwr-stg iam add-user-to-group \
  --user-name "${AWS_STG_USER}" --group-name liveforge
success "Added to liveforge."

info "Creating programmatic access key for '${AWS_STG_USER}'..."
STG_KEY_JSON=$(aws --profile alwr-stg iam create-access-key \
  --user-name "${AWS_STG_USER}" \
  --output json --query 'AccessKey.{KeyId:AccessKeyId,Secret:SecretAccessKey}')
STG_KEY_ID=$(echo "$STG_KEY_JSON"    | jq -r '.KeyId')
STG_KEY_SECRET=$(echo "$STG_KEY_JSON" | jq -r '.Secret')
success "Access key created for staging."

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}=== Onboarding Complete ===${NC}"
echo ""
echo -e "  Jenkins URL:         ${JENKINS_URL}"
echo -e "  Jenkins username:    ${USERNAME}"
echo -e "  Jenkins password:    ${TEMP_PASS}  (from \$JENKINS_PASSWORD)"
echo -e "  Jenkins role:        engineer"
echo ""
echo -e "  AWS Dev user:        ${AWS_DEV_USER}"
echo -e "  AWS Dev groups:      KubernetesDevelopers"
echo -e "  AWS Dev access:      programmatic only (no console login)"
echo -e "  AWS Dev key ID:      ${DEV_KEY_ID}"
echo -e "  AWS Dev secret:      ${DEV_KEY_SECRET}"
echo ""
echo -e "  AWS Staging user:    ${AWS_STG_USER}"
echo -e "  AWS Staging groups:  KubernetesDevelopers, liveforge"
echo -e "  AWS Staging access:  programmatic only (no console login)"
echo -e "  AWS Staging key ID:  ${STG_KEY_ID}"
echo -e "  AWS Staging secret:  ${STG_KEY_SECRET}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Share Jenkins password with the developer via a secure channel."
echo "  2. Ask the developer to reset their Jenkins password on first login."
echo "  3. Share the AWS key ID + secret for EACH account via a secure channel."
echo "  4. Developer adds credentials to ~/.aws/credentials under [alwr-dev] and [alwr-stg]."
echo "  5. Confirm EKS kubectl access by asking developer to run: kubectl get pods -n <namespace>"
echo ""
