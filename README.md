# Beadster

POC for syncing local beads issues to cloud and viewing them on web

## Components

- **API** (`src/api`) - Cloudflare Workers API with D1 database
- **Web** (`src/web`) - Astro website deployed to Cloudflare Workers
- **Sync** (`src/sync`) - Swift daemon that syncs local .beads to cloud

## URLs

- Web: https://beadster-dev-web.systemoperator.workers.dev/
- API: https://beadster-dev-api.systemoperator.workers.dev/

## Quick Start

### Sync issues to cloud

One-time sync (run after creating/updating issues):
```bash
./scripts/sync-once.sh
```

Auto-sync daemon (keeps running, watches for changes):
```bash
./scripts/sync-daemon.sh
```

### Build sync daemon

```bash
cd src/sync
swift build
```

## Architecture

Local .beads DB → Sync Daemon → Cloud API → D1 Database → Web UI

1. Create issues locally with `bd create`
2. Sync daemon reads .beads/beadster.db
3. Pushes to cloud via API
4. Web UI queries D1 directly
