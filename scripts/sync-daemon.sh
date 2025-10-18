#!/bin/bash
# Run sync daemon in the background - auto-syncs when issues change
# Run this to keep issues automatically synced

cd "$(dirname "$0")/../src/sync"

echo "🚀 Starting Beadster sync daemon..."
echo "📝 Watches for changes and syncs automatically"
echo "🛑 Press Ctrl+C to stop"
echo ""

.build/debug/BeadsterSync
