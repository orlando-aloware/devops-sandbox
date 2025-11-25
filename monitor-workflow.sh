#!/bin/bash
set -euo pipefail

REPO="aloware/devops-sandbox"
WORKFLOW="k8s-long-run.yml"
BRANCH="optimize-zap-pipeline"

echo "======================================"
echo "Fetching latest workflow runs"
echo "======================================"

# Show latest runs
gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --branch "$BRANCH" \
  --limit 5

echo ""
echo "======================================"
echo "Select a run to monitor (or press Ctrl+C to exit)"
echo "======================================"
echo ""

# Get the latest run ID
RUN_ID=$(gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --branch "$BRANCH" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
  echo "No workflow runs found!"
  exit 1
fi

echo "Monitoring Run ID: $RUN_ID"
echo "View in browser: https://github.com/$REPO/actions/runs/$RUN_ID"
echo ""

# Watch the workflow
gh run watch "$RUN_ID" --repo "$REPO"
