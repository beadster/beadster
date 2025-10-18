#!/bin/bash
# Run sync daemon in the background - auto-syncs when issues change
# Run this to keep issues automatically synced

cd "$(dirname "$0")/../src/sync"

echo "🔨 Building sync daemon..."
swift build
if [ $? -ne 0 ]; then
  echo "❌ Build failed"
  exit 1
fi

echo ""
echo "🚀 Starting Beadster sync daemon..."
echo "📝 Watches for changes and syncs automatically"
echo "🛑 Press Ctrl+C to stop"
echo ""

.build/debug/BeadsterSync
