# DVPS-292 Session Handoff — Increase Max Memory for Horizon Queues (Dev)

## Status: PR open, deployed to dev, trial reset applied

---

## What was done

### 1. Horizon memory bump — `api-core` (branch `fix/DVPS-292-increase-memory-queues`)

**File**: `horizon/horizon.dev.php`

Added `'memory' => 256` to two supervisors that were hitting the default 128MB limit on the dev environment:

| Supervisor | Queue | Default Memory | New Memory |
|---|---|---|---|
| `supervisor-account-setup` | `account-setup-queue` | 128 MB (Horizon default) | 256 MB |
| `supervisor-exports-long-running` | `exports-long-running-queue` | 128 MB (Horizon default) | 256 MB |

**Why**: Workers on these queues were being killed by OOM on the dev EKS cluster, causing jobs to silently fail or retry indefinitely.

### 2. Reset-trial-period skill — `api-core` (same branch)

**File**: `.claude/skills/reset-trial-period/SKILL.md`

New Claude/Copilot skill for resetting expired trial accounts on dev/staging clusters. Documents the full procedure: connect to cluster → find company → update `companies` + `subscriptions` tables → verify. Invoke with `/reset-trial-period` or natural language like "reset trial".

### 3. Trial reset applied (DB change, not in code)

Reset trial for company **5321** (`orlando@aloware.com`) in cluster `aloware-dev-uswest2-eks-cluster-cr-01`:

| Column | Before | After |
|---|---|---|
| `companies.trial_start_at` | 2026-02-02 08:00:00 | 2026-04-06 21:21:19 |
| `companies.trial_ends_at` | 2026-02-09 07:59:59 | 2026-05-06 21:21:19 |
| `subscriptions.status` (id=2377) | cancelled | in_trial |
| `subscriptions.trial_start` | 2026-02-02 08:00:00 | 2026-04-06 21:21:19 |
| `subscriptions.trial_end` | 2026-02-09 07:59:59 | 2026-05-06 21:21:19 |

Verified: `trial_status=3` (ACTIVE), `isUsable=true`.

---

## PR

| Field | Value |
|---|---|
| PR | [#14148](https://github.com/aloware/api-core/pull/14148) |
| Branch | `fix/DVPS-292-increase-memory-queues` |
| Base | `develop` |
| Commits | 3 (`a76b5da`, `6348e3c`, `2f5f141`) |

---

## Cluster access

```bash
aws eks update-kubeconfig --region us-west-2 --name aloware-dev-uswest2-eks-cluster-cr-01
kubectl get pods -n app -l app=api-core
```

Pod used during this session: `api-core-685c466b4b-7z84k`

---

## Key files

| File | What |
|---|---|
| `horizon/horizon.dev.php` | Horizon supervisor config for dev environment |
| `.claude/skills/reset-trial-period/SKILL.md` | Trial reset procedure skill |
| `app/Models/Company.php` | `getTrialStatusAttribute()`, `isUsable()`, trial constants |
| `app/Models/Subscription.php` | Subscription status constants |

---

## Notes

- The trial reset is a **DB-only change** — Chargebee is not synced. This is fine for dev.
- The `getEffectiveTrialPeriodDays()` method throws a TypeError when `plan.trial_period_days` is null — observed but doesn't block the fix.
- Horizon default memory is 128MB. Only the two supervisors above needed the bump; other supervisors may need it too if they start OOMing.
- The `memory` setting in `horizon.dev.php` only affects the dev environment. Production/staging use their own horizon config files.
