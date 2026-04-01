#!/usr/bin/env bash
# =============================================================================
# seed_and_break.sh — DMS Sandbox Test Driver (DVPS-257)
#
# Steps:
#   1. seed     — create the 'orders' table and insert sample rows into RDS
#   2. start    — start the DMS replication task (full-load-and-cdc)
#   3. break    — run ALTER TABLE (add column) to put 'orders' into Table error
#   4. verify   — invoke Lambda CHECK to confirm errored tables
#   5. alert    — invoke Lambda ALERT to trigger SNS email
#   6. reload   — invoke Lambda RELOAD to recover DMS
#
# Run individual steps: bash seed_and_break.sh <step>
# Run full cycle:       bash seed_and_break.sh all
#
# Requirements: aws CLI v2, mysql client
# =============================================================================
set -euo pipefail

PROFILE="aquaware"
REGION="us-east-1"
AWS="aws --profile ${PROFILE} --region ${REGION}"

# Populated from terraform output after apply
RDS_ENDPOINT="${RDS_ENDPOINT:-$(terraform -chdir="$(dirname "$0")" output -raw rds_endpoint 2>/dev/null || echo '')}"
DMS_TASK_ARN="${DMS_TASK_ARN:-$(terraform -chdir="$(dirname "$0")" output -raw dms_task_arn 2>/dev/null || echo '')}"
LAMBDA_NAME="${LAMBDA_NAME:-$(terraform -chdir="$(dirname "$0")" output -raw lambda_function_name 2>/dev/null || echo '')}"
DB_PASS="SandboxPass123!"
DB_HOST="${RDS_ENDPOINT%%:*}"  # strip port

if [[ -z "${DB_HOST}" || -z "${DMS_TASK_ARN}" || -z "${LAMBDA_NAME}" ]]; then
  echo "ERROR: Run 'terraform apply' first or set RDS_ENDPOINT, DMS_TASK_ARN, LAMBDA_NAME env vars."
  exit 1
fi

MYSQL="mysql -h ${DB_HOST} -u admin -p${DB_PASS} sandbox"

step_seed() {
  echo "==> [1/6] Seeding RDS with 'orders' table..."
  ${MYSQL} << 'SQL'
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  customer   VARCHAR(100) NOT NULL,
  amount     DECIMAL(10,2) NOT NULL,
  created_at DATETIME DEFAULT NOW()
);
INSERT INTO orders (customer, amount) VALUES
  ('Alice',  99.99),
  ('Bob',   149.00),
  ('Carol',  25.50),
  ('Dave',  200.00),
  ('Eve',    75.00);
SELECT COUNT(*) AS seeded_rows FROM orders;
SQL
  echo "    Seed done."
}

step_start() {
  echo "==> [2/6] Starting DMS replication task (full-load-and-cdc)..."
  ${AWS} dms start-replication-task \
    --replication-task-arn "${DMS_TASK_ARN}" \
    --start-replication-task-type start-replication

  echo "    Waiting 60s for full-load to complete before breaking schema..."
  sleep 60

  STATUS=$(${AWS} dms describe-replication-tasks \
    --filters "Name=replication-task-arn,Values=${DMS_TASK_ARN}" \
    --query 'ReplicationTasks[0].Status' --output text)
  echo "    DMS task status: ${STATUS}"
}

step_break() {
  echo "==> [3/6] Breaking DMS: ALTER TABLE to add an unexpected column..."
  # Adding a NOT NULL column without a default causes DMS to error on the table
  # because the ongoing CDC stream doesn't match the target schema.
  ${MYSQL} << 'SQL'
ALTER TABLE orders ADD COLUMN priority TINYINT NOT NULL DEFAULT 0;
INSERT INTO orders (customer, amount, priority) VALUES ('Frank', 50.00, 1);
SELECT 'Schema changed — DMS should enter Table error state shortly.' AS status;
SQL
  echo "    Waiting 30s for DMS to detect the schema change..."
  sleep 30

  echo "    Current DMS table statistics:"
  ${AWS} dms describe-table-statistics \
    --replication-task-arn "${DMS_TASK_ARN}" \
    --query 'TableStatistics[*].{Table:TableName,State:TableState}' \
    --output table
}

step_verify() {
  echo "==> [4/6] Invoking Lambda CHECK (dry-run, no side-effects)..."
  ${AWS} lambda invoke \
    --function-name "${LAMBDA_NAME}" \
    --payload '{"mode":"CHECK"}' \
    --cli-binary-format raw-in-base64-out \
    /tmp/check_response.json
  echo "    Response:"
  cat /tmp/check_response.json | python3 -m json.tool
}

step_alert() {
  echo "==> [5/6] Invoking Lambda ALERT (sends email if tables in error)..."
  ${AWS} lambda invoke \
    --function-name "${LAMBDA_NAME}" \
    --payload '{"mode":"ALERT"}' \
    --cli-binary-format raw-in-base64-out \
    /tmp/alert_response.json
  echo "    Response:"
  cat /tmp/alert_response.json | python3 -m json.tool
  echo "    Check orlando@aloware.com for the alert email."
}

step_reload() {
  echo "==> [6/6] Invoking Lambda RELOAD (stop + reload-target)..."
  ${AWS} lambda invoke \
    --function-name "${LAMBDA_NAME}" \
    --payload '{"mode":"RELOAD"}' \
    --cli-binary-format raw-in-base64-out \
    /tmp/reload_response.json
  echo "    Response:"
  cat /tmp/reload_response.json | python3 -m json.tool
  echo "    DMS task will reload. Monitor via AWS Console or re-run step_verify."
}

case "${1:-all}" in
  seed)   step_seed   ;;
  start)  step_start  ;;
  break)  step_break  ;;
  verify) step_verify ;;
  alert)  step_alert  ;;
  reload) step_reload ;;
  all)
    step_seed
    step_start
    step_break
    step_verify
    step_alert
    echo ""
    echo "Full cycle complete. Tables should be in error state and email sent."
    echo "Run:  bash seed_and_break.sh reload  — to test the RELOAD path."
    ;;
  *)
    echo "Usage: $0 [seed|start|break|verify|alert|reload|all]"
    exit 1
    ;;
esac
