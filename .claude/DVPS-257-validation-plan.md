# DVPS-257 — DMS Healthcheck Sandbox Validation Plan

> **SESSION HANDOFF** — Infrastructure is live. Continue at Step 1 (SNS confirmation) below.
> AWS account: aquaware (711387135481, us-east-1)
> Terraform state: `/Users/orlando/_tmp/alwr/devops-sandbox/dms-healthcheck-sandbox/`
> Resources suffix: `c428d8b2`

## Goal
End-to-end validation of the Lambda-based DMS monitor in the `aquaware` AWS account (711387135481, us-east-1) before deploying to staging.

---

## Prerequisites
- AWS CLI v2 installed, `aquaware` profile configured and working (`aws s3 ls --profile aquaware` returns results)
- MySQL client installed (`brew install mysql-client` if missing)
- `terraform` CLI installed
- Working directory: `devops-sandbox/dms-healthcheck-sandbox/`
- Confirm `.terraform/` providers are present locally (run `terraform init` if not)

---

## Step 0 — Apply Infrastructure

```bash
cd /Users/orlando/_tmp/alwr/devops-sandbox/dms-healthcheck-sandbox
terraform init   # re-download providers if needed
terraform apply -var="aws_profile=aquaware" -var="alert_email=orlando@aloware.com"
```

**What gets created:**
| Resource | Details |
|---|---|
| RDS MySQL 8.0 | t3.micro, binlog CDC enabled, DB `sandbox` |
| Redshift cluster | dc2.large, DB `sandbox` (DMS target) |
| DMS replication instance | dms.t3.micro |
| DMS source endpoint | MySQL (RDS) |
| DMS target endpoint | Redshift |
| DMS task | `full-load-and-cdc` on `sandbox.orders`, NOT auto-started |
| SNS topic + email sub | `orlando@aloware.com` — **must confirm before testing** |
| Lambda | Python 3.12, `MODE=ALERT`, 180s timeout |
| EventBridge rule | Daily cron, **DISABLED** by default |

After apply, note the outputs:
```bash
terraform output
```

---

## Step 1 — Confirm SNS Email Subscription

After `terraform apply`, AWS sends a confirmation email to `orlando@aloware.com`.

1. Open the email: **"AWS Notification - Subscription Confirmation"**
2. Click **Confirm subscription**
3. Without this, Lambda ALERT mode will silently deliver nothing

---

## Step 2 — Seed RDS + Start DMS

```bash
bash seed_and_break.sh seed
bash seed_and_break.sh start
```

- `seed`: creates `orders` table with 5 rows in RDS
- `start`: starts DMS task in `start-replication` mode, waits 60s for full-load

**Verify DMS is running:**
```bash
aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=$(terraform output -raw dms_task_arn)" \
  --profile aquaware --region us-east-1 \
  --query 'ReplicationTasks[0].Status' --output text
# Expected: running
```

---

## Step 3 — Dry-Run CHECK (no errors yet)

Invoke Lambda in CHECK mode — should report 0 errored tables:

```bash
LAMBDA=$(terraform output -raw lambda_function_name)
aws lambda invoke \
  --function-name $LAMBDA \
  --profile aquaware --region us-east-1 \
  --payload '{"mode":"CHECK"}' --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

**Expected:** `{"mode": "CHECK", "errored_tables": [], "count": 0}`

---

## Step 4 — Break DMS

Run the ALTER TABLE that triggers `Table error` state:

```bash
bash seed_and_break.sh break
```

This runs:
```sql
ALTER TABLE orders ADD COLUMN priority TINYINT NOT NULL DEFAULT 0;
INSERT INTO orders (customer, amount, priority) VALUES ('Frank', 50.00, 1);
```

Wait 30–60s for DMS to register the error, then verify:
```bash
bash seed_and_break.sh verify
# Lambda CHECK should now return errored_tables: ["sandbox.orders"]
```

---

## Step 5 — ALERT Mode (email)

```bash
bash seed_and_break.sh alert
```

Or manually:
```bash
aws lambda invoke \
  --function-name $LAMBDA \
  --profile aquaware --region us-east-1 \
  --payload '{"mode":"ALERT"}' --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

**Expected:**
- Response: `{"mode": "ALERT", "errored_tables": ["sandbox.orders"], "count": 1, "alert_sent": true}`
- Email arrives at `orlando@aloware.com` with subject: `[DMS ALERT] Table errors detected`
- Email body includes recovery CLI commands (RELOAD and CHECK)

---

## Step 6 — RELOAD Mode (recovery)

```bash
bash seed_and_break.sh reload
```

Or manually:
```bash
aws lambda invoke \
  --function-name $LAMBDA \
  --profile aquaware --region us-east-1 \
  --payload '{"mode":"RELOAD"}' --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

**Expected:**
- Lambda stops DMS task, waits for STOPPED, restarts with `reload-target`
- Response: `{"mode": "RELOAD", "status": "reload started"}`

After ~2min, check DMS status is back to `running`:
```bash
aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=$(terraform output -raw dms_task_arn)" \
  --profile aquaware --region us-east-1 \
  --query 'ReplicationTasks[0].Status' --output text
```

---

## Step 7 — Teardown

When validation is complete, destroy all sandbox resources:

```bash
terraform destroy -var="aws_profile=aquaware" -var="alert_email=orlando@aloware.com"
```

Confirm with `yes`. This removes all resources and avoids ongoing costs (Redshift dc2.large ~$0.25/hr).

---

## Step 8 — Deploy to Staging (post-validation)

Once sandbox passes:

1. **Run setup.sh against staging account** (225989345843):
   ```bash
   cd jenkins-pipeline-collection/dms-healthcheck/lambda
   # Edit setup.sh: verify DMS_TASK_ARN and SNS email
   bash setup.sh
   ```
2. **Register Jenkins pipeline**: point to `jenkins-pipeline-collection/dms-healthcheck/Jenkinsfile`
3. **Confirm SNS subscription** in staging account email
4. **Test manually**: trigger Jenkins pipeline once, verify it reads DMS stats

---

## Validation Checklist

- [ ] `terraform apply` succeeds cleanly
- [ ] SNS subscription email confirmed
- [ ] `seed` + `start` succeeds, DMS status = `running`
- [ ] CHECK mode returns 0 errors when DMS is healthy
- [ ] `break` triggers `Table error` on `sandbox.orders`
- [ ] CHECK mode detects `sandbox.orders` as errored
- [ ] ALERT mode sends email with recovery instructions
- [ ] RELOAD mode stops and restarts DMS successfully
- [ ] DMS returns to `running` after reload
- [ ] `terraform destroy` cleans up all resources
