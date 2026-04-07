# DVPS-257 Session Handoff — DMS Monitor Solution (Staging)

## Status: Infrastructure live, validation pending

---

## What was built

### 1. Jenkins pipeline — `jenkins-pipeline-collection` (main, commit `27f75c4`)
- **File**: `dms-healthcheck/Jenkinsfile`
- Nightly cron `0 4 * * *` (10pm CST)
- Stage 1: checks GitHub API for non-prerelease releases published in last 25h
- Stage 2: `aws dms describe-table-statistics` against staging DMS task
- Stage 3: `input` step (2hr timeout) showing errored tables + confirmation
- Stage 4: stop → wait for STOPPED → start reload-target
- Uses credential `aws-credentials-profiles` with `staging` profile

### 2. Lambda function — `jenkins-pipeline-collection` (main, commit `27f75c4`)
- **File**: `dms-healthcheck/lambda/handler.py`
- **File**: `dms-healthcheck/lambda/setup.sh` (manual deploy to staging)
- Modes: `ALERT` (default env var), `CHECK` (dry-run), `RELOAD` (stop+restart)
- Event payload `{"mode":"..."}` overrides the env var for one-off invocations
- `send_alert()` includes HOW TO RECOVER section with copy-paste CLI commands
- **Staging DMS task ARN**: `arn:aws:dms:us-west-2:225989345843:task:4CAINQZGBFDG5JRHJWEF3XL6LI`

### 3. Terraform sandbox — `devops-sandbox` (branch `feature/DVPS-257/dms-healthcheck-sandbox`, commit `864b4c9`)
- **Dir**: `dms-healthcheck-sandbox/`
- AWS account: `aquaware` (711387135481), region: `us-east-1`
- GitHub: `https://github.com/orlando-aloware/devops-sandbox`

---

## Live infrastructure (terraform apply completed April 1, 2026)

| Resource | Value |
|---|---|
| RDS source (MySQL 8.0) | `dms-sandbox-c428d8b2-mysql.con0qiowui9u.us-east-1.rds.amazonaws.com:3306` |
| RDS target (MySQL 8.0) | internal to VPC, accessed via DMS endpoint |
| DMS replication instance | `dms-sandbox-c428d8b2-dms` (dms.t3.medium) |
| DMS task ARN | `arn:aws:dms:us-east-1:711387135481:task:ZK2J7XMEPFGKREQLFNY62DOADY` |
| Lambda | `dms-sandbox-c428d8b2-healthcheck` |
| SNS topic | `arn:aws:sns:us-east-1:711387135481:dms-sandbox-c428d8b2-alerts` |
| EventBridge rule | `dms-sandbox-c428d8b2-nightly` (DISABLED by default) |

> **COST WARNING**: Two RDS t3.micro instances running. Run `terraform destroy` when done.

---

## Where we left off — next step is Step 1

### Step 1 — Confirm SNS email subscription (BLOCKING)
- Check `orlando@aloware.com` inbox for: **"AWS Notification - Subscription Confirmation"**
- From: `no-reply@sns.amazonaws.com`
- Click **Confirm subscription**
- Without this, Lambda ALERT sends nothing

### Step 2 — Seed + start DMS
```bash
cd /Users/orlando/_tmp/alwr/devops-sandbox/dms-healthcheck-sandbox
bash seed_and_break.sh seed
bash seed_and_break.sh start
```
Script auto-reads terraform outputs for RDS endpoint, DMS task ARN, Lambda name.

### Step 3 — CHECK baseline (0 errors expected)
```bash
aws lambda invoke --function-name dms-sandbox-c428d8b2-healthcheck \
  --profile aquaware --region us-east-1 \
  --payload '{"mode":"CHECK"}' --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
# Expected: {"mode": "CHECK", "errored_tables": [], "count": 0}
```

### Step 4 — Break DMS
```bash
bash seed_and_break.sh break
# Wait 30-60s, then:
bash seed_and_break.sh verify
# Expected: errored_tables: ["sandbox.orders"]
```

### Step 5 — ALERT (send email)
```bash
bash seed_and_break.sh alert
# Expected: email arrives at orlando@aloware.com with recovery instructions
```

### Step 6 — RELOAD (recovery)
```bash
bash seed_and_break.sh reload
# Lambda stops + restarts DMS with reload-target
# Check status after ~2min:
aws dms describe-replication-tasks \
  --filters "Name=replication-task-arn,Values=arn:aws:dms:us-east-1:711387135481:task:ZK2J7XMEPFGKREQLFNY62DOADY" \
  --profile aquaware --region us-east-1 \
  --query 'ReplicationTasks[0].Status' --output text
```

### Step 7 — Teardown
```bash
cd /Users/orlando/_tmp/alwr/devops-sandbox/dms-healthcheck-sandbox
terraform destroy -var="aws_profile=aquaware" -var="alert_email=orlando@aloware.com"
```

### Step 8 — Deploy to staging (after sandbox passes)
```bash
cd /Users/orlando/_tmp/alwr/jenkins-pipeline-collection/dms-healthcheck/lambda
# Review setup.sh first — verify DMS_TASK_ARN and SNS email
bash setup.sh
# Then register the Jenkins pipeline pointing to:
# jenkins-pipeline-collection/dms-healthcheck/Jenkinsfile
```

---

## Key config values

| Key | Value |
|---|---|
| Staging DMS task ARN | `arn:aws:dms:us-west-2:225989345843:task:4CAINQZGBFDG5JRHJWEF3XL6LI` |
| Staging AWS account | 225989345843 |
| Aquaware AWS account | 711387135481 |
| Aquaware profile | `aquaware` |
| GH App ID | 1157885 |
| GH Installation ID | 61798182 |
| Jenkins credential | `aws-credentials-profiles` (staging profile) |

---

## Repo locations

| Repo | Path | Branch |
|---|---|---|
| jenkins-pipeline-collection | `/Users/orlando/_tmp/alwr/jenkins-pipeline-collection` | `main` |
| devops-sandbox | `/Users/orlando/_tmp/alwr/devops-sandbox` | `feature/DVPS-257/dms-healthcheck-sandbox` |

---

## Validation checklist

- [ ] SNS subscription email confirmed
- [ ] `seed` + `start` succeeds, DMS status = `running`
- [ ] CHECK mode returns 0 errors (healthy baseline)
- [ ] `break` triggers `Table error` on `sandbox.orders`
- [ ] CHECK detects the errored table
- [ ] ALERT sends email with recovery instructions
- [ ] RELOAD stops and restarts DMS successfully
- [ ] DMS returns to `running` after reload
- [ ] `terraform destroy` cleans up all resources
- [ ] `bash setup.sh` deploys Lambda to staging
- [ ] Jenkins pipeline registered and triggers correctly
