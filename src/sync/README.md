# Beadster Sync Daemon

Swift CLI daemon that syncs local .beads/ directories to Beadster cloud

## features

- watches .beads/ directories for changes
- pushes issues to cloud (local → cloud)
- pulls changes from cloud (cloud → local)
- bidirectional sync
- native macOS FSEvents file watching

## build

```bash
swift build -c release
```

binary will be at: `.build/release/BeadsterSync`

## install

```bash
swift build -c release
cp .build/release/BeadsterSync /usr/local/bin/beadster-sync
```

## configure

create `~/.beadster/config.json`:

```json
{
  "apiKey": "your-api-key-here",
  "apiUrl": "https://api.beadster.com",
  "sources": [
    {
      "name": "main-app",
      "path": "/Users/you/projects/main-app"
    },
    {
      "name": "side-project",
      "path": "/Users/you/projects/side-project"
    }
  ]
}
```

## run

```bash
beadster-sync
```

or from source:

```bash
swift run
```

## how it works

1. reads config from ~/.beadster/config.json
2. for each source:
   - opens .beads/beads.db (read-only)
   - extracts all issues
   - extracts session metadata from labels
   - pushes to cloud api
3. watches .beads/issues/ for changes
4. polls cloud every 10s for changes
5. applies cloud changes via bd cli

## session tracking

automatically extracts session metadata from labels:

- `session:xxx` → session_id
- `client:xxx` → client (claude-code, claude-desktop, etc)
- `project:xxx` → project_name

this metadata is sent to cloud for session grouping

## for teams without macOS

use github actions to sync instead - see `.github/workflows/beadster-sync.yml`
