# DevOps Sandbox — Long-running K8s test demo

This repository contains a tiny Node.js Express app and a Cypress test that is intentionally long-running (~3 hours total) to demonstrate running long jobs inside a Kubernetes Job from a GitHub Actions workflow.

What was added
- `index.js` — minimal Express app on port 3000
- `package.json` — scripts `start` and `cypress:run`
- `cypress.config.js` — Cypress config with large timeouts
- `cypress/e2e/long_run.cy.js` — test that waits ~1 hour then 2 hours
- `.github/workflows/k8s-long-run.yml` — GitHub Actions workflow that:
  - uses `gh` to create/push `aloware/devop-sandbox` repo (if missing)
  - configures AWS credentials and updates kubeconfig for EKS
  - launches a Kubernetes `Job` using `cypress/included` image which clones the repo, starts the app, runs Cypress tests, and exits with the test result

Required secrets and variables for the workflow

**Repository Variables** (Settings > Secrets and variables > Actions > Variables tab):
- `AWS_REGION` — AWS region for EKS cluster (e.g., `us-west-2`)

**Repository Secrets** (Settings > Secrets and variables > Actions > Secrets tab):
- `GH_TOKEN` — GitHub token with permissions to create/push repos
- `AWS_ACCESS_KEY_ID` — AWS access key with EKS access
- `AWS_SECRET_ACCESS_KEY` — AWS secret key
- `EKS_CLUSTER_NAME` — the EKS cluster name

**Environment Secrets** (optional, for `dev` environment):
- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` — scoped to dev environment

Pod identification
- The Kubernetes Job is named `long-run-test-job-<workflow-run-id>` (e.g., `long-run-test-job-12345678`)
- The pod name will be `long-run-test-job-<workflow-run-id>-<random-hash>` (e.g., `long-run-test-job-12345678-x7k2m`)
- Labels: `environment=dev`, `app=devops-sandbox-test`
- To find your pod: `kubectl get pods -l app=devops-sandbox-test -n default`

Notes and caveats
- The Cypress test intentionally includes long `cy.wait()` durations (1 hour + 2 hours) to make the workflow run ~3 hours. Adjust or remove these waits in `cypress/e2e/long_run.cy.js` when you don't want to consume runtime minutes.
- The workflow relies on the `cypress/included` image so Cypress is available in the pod; the pod clones the repo and runs `npm start` and `npm run cypress:run`.
- The workflow sets a 4-hour wait timeout for the job — change `timeout-minutes` in the workflow if you expect different durations.
- The Job runs in the `default` namespace; modify the workflow to use a different namespace if needed.
