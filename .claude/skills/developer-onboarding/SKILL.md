---
name: developer-onboarding
description: "Use when onboarding a new developer who needs access to Jenkins, AWS Dev, and AWS Staging environments. Triggers on: new developer, onboard developer, provision access, create user, add engineer, new employee setup."
argument-hint: "<email> [username]"
---

# Developer Onboarding

Provisions a new developer's access across three systems in one shot:

| System | What gets created |
|--------|------------------|
| Jenkins | User account + `engineer` global role |
| AWS Dev (333629833033) | IAM user `name+dev@domain` → group `KubernetesDevelopers` → programmatic access key |
| AWS Staging (225989345843) | IAM user `name+staging@domain` → groups `KubernetesDevelopers`, `liveforge` → programmatic access key |

## Prerequisites

Before running, ensure these are set in your shell:

```bash
export JENKINS_USER="<your-jenkins-admin-user>"
export JENKINS_TOKEN_NAME="<token-name>"          # informational
export JENKINS_TOKEN="<your-jenkins-api-token>"
```

AWS credentials profiles `[alwr-dev]` and `[alwr-stg]` must exist in `~/.aws/credentials`.
> Profiles are set up by `_connect_d.sh` (dev, 333629833033) and `_connect_s.sh` (staging, 225989345843).

`jq` and the AWS CLI must be installed and on `$PATH`.

## When to Use

Invoke this skill whenever a new engineer joins and needs:
- Jenkins CI/CD access
- Kubernetes access in dev and/or staging via IAM groups

## Procedure

### 1. Gather inputs

Ask the user for:
- **`EMAIL`** — the developer's work email (e.g. `john.doe@aloware.com`)
- **`USERNAME`** _(optional)_ — Jenkins username. Defaults to the first name parsed from the email local part (e.g. `john` from `john.doe@aloware.com`).

### 2. Derive identifiers

| Variable | Rule | Example |
|----------|------|---------|
| Jenkins username | First segment of local part before `.` or `_` | `john` |
| AWS Dev username | Insert `+dev` before `@` | `john.doe+dev@aloware.com` |
| AWS Staging username | Insert `+staging` before `@` | `john.doe+staging@aloware.com` |

### 3. Run the onboarding script

```bash
# From the repo root (or any directory):
bash devops-sandbox/.claude/skills/developer-onboarding/scripts/onboard.sh <EMAIL> [USERNAME]
```

The script will confirm the derived values and ask for a `y` confirmation before making any changes.

### 4. What the script does

**Jenkins** (via Script Console + Role Strategy plugin REST API):
1. Calls `POST /scriptText` with a Groovy snippet to create the account.
2. Calls `POST /role-strategy/strategy/assignRole` with `type=globalRoles&roleName=engineer&sid=<username>`.

**AWS Dev** (profile `alwr-dev`):
1. `aws iam create-user --user-name <email+dev>`
2. `aws iam add-user-to-group --group-name KubernetesDevelopers`
3. `aws iam create-access-key` — **programmatic access only, no console login profile created**
4. Access Key ID + Secret printed to stdout for secure handoff

**AWS Staging** (profile `alwr-stg`):
1. `aws iam create-user --user-name <email+staging>`
2. `aws iam add-user-to-group --group-name KubernetesDevelopers`
3. `aws iam add-user-to-group --group-name liveforge`
4. `aws iam create-access-key` — **programmatic access only, no console login profile created**
5. Access Key ID + Secret printed to stdout for secure handoff

### 5. Post-run checklist

- [ ] Share Jenkins **password** with the developer through a secure channel (1Password, Signal, etc.)
- [ ] Ask the developer to reset their Jenkins password on first login
- [ ] Share **both AWS Access Key ID + Secret** (dev and staging) via a secure channel
- [ ] Developer adds credentials to `~/.aws/credentials` under `[alwr-dev]` and `[alwr-stg]`
- [ ] Confirm EKS access: `kubectl get pods -n <namespace>` from the developer's machine

## Error Handling

| Situation | Behaviour |
|-----------|-----------|
| Jenkins user already exists | Skips creation, still re-assigns role |
| AWS IAM user already exists | Warns and skips; group membership steps still run |
| Role Strategy API non-200 | Emits warning with manual verification URL |
| Missing env var | Script exits immediately with clear message |

## Reference

- Jenkins Role Strategy plugin API: `POST /role-strategy/strategy/assignRole`
- Jenkins Script Console: `POST /scriptText`
- AWS CLI docs: `aws iam create-user`, `aws iam add-user-to-group`
- Connect scripts: `orlando-aloware-utils/bin/_connect_d.sh` (dev), `_connect_s.sh` (staging)
