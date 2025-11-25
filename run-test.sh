#!/bin/sh
set -e
echo "=== Testing locally in cypress/included container ==="
echo "Installing dependencies..."
npm ci --prefer-offline
echo "Starting app in background..."
npm start &
APP_PID=$!
sleep 5
echo "Testing app health..."
curl -s http://localhost:3000/health | grep -q "ok" && echo "✅ App is healthy" || (echo "❌ App health check failed" && exit 1)
echo "Running quick Cypress test..."
npx cypress run --spec cypress/e2e/quick_test.cy.js --config video=false
EXIT_CODE=$?
echo "Test completed with exit code: $EXIT_CODE"
kill $APP_PID 2>/dev/null || true
exit $EXIT_CODE
