#!/bin/bash
# One-time sync of local beads to cloud
# Run this after creating/updating issues locally

cd "$(dirname "$0")/../src/sync"

echo "🔄 Starting one-time sync..."

# Run sync and auto-kill after 5 seconds
(.build/debug/BeadsterSync &)
SYNC_PID=$!
sleep 5
kill $SYNC_PID 2>/dev/null || true

echo ""
echo "✅ Sync complete! Check https://beadster-dev-web.systemoperator.workers.dev/"
