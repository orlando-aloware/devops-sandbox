#!/bin/bash
set -euo pipefail

REPO="aloware/devops-sandbox"
WORKFLOW="k8s-long-run.yml"
BRANCH="optimize-zap-pipeline"

echo "======================================"
echo "Triggering workflow: $WORKFLOW"
echo "Repository: $REPO"
echo "Branch: $BRANCH"
echo "======================================"

# Trigger the workflow
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$BRANCH"

echo "✅ Workflow triggered successfully!"
echo ""
echo "Waiting for workflow run to start..."
sleep 5

# Get the latest run ID
RUN_ID=$(gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --branch "$BRANCH" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')

echo "Run ID: $RUN_ID"
echo "View in browser: https://github.com/$REPO/actions/runs/$RUN_ID"
echo ""
echo "======================================"
echo "Monitoring workflow (press Ctrl+C to stop monitoring, workflow will continue)"
echo "======================================"
echo ""

# Watch the workflow
gh run watch "$RUN_ID" --repo "$REPO" --exit-status

echo ""
echo "======================================"
echo "Workflow completed!"
echo "======================================"
