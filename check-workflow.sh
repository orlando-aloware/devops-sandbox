#!/bin/bash
set -euo pipefail

REPO="aloware/devops-sandbox"
WORKFLOW="k8s-long-run.yml"
BRANCH="optimize-zap-pipeline"

echo "======================================"
echo "Latest workflow runs for: $WORKFLOW"
echo "======================================"
echo ""

# Show latest runs with more details
gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --branch "$BRANCH" \
  --limit 10

echo ""
echo "======================================"
echo "To monitor a specific run, use:"
echo "  gh run watch <RUN_ID> --repo $REPO"
echo ""
echo "To view logs:"
echo "  gh run view <RUN_ID> --repo $REPO --log"
echo "======================================"
