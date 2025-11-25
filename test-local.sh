#!/bin/bash
set -euo pipefail

echo "=== Local test emulating GHA runner ==="

# Install Node.js (similar to what cypress/included has)
echo "Installing Node.js and npm..."
apt-get update -y
apt-get install -y curl git
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"

# Navigate to workspace
cd /workspace
echo "Working directory: $(pwd)"

# Install dependencies
echo "Installing dependencies..."
npm ci

# Start the app in background
echo "Starting Express app in background..."
npm start &
APP_PID=$!
sleep 5

# Check if app is running
if curl -s http://localhost:3000/health | grep -q "ok"; then
  echo "✅ App is running and healthy"
else
  echo "❌ App health check failed"
  exit 1
fi

# Run Cypress tests (with shorter timeout for local testing)
echo "Running Cypress tests..."
npm run cypress:run || EXIT_CODE=$?

echo "Tests completed with exit code: ${EXIT_CODE:-0}"

# Cleanup
kill $APP_PID 2>/dev/null || true

exit ${EXIT_CODE:-0}
