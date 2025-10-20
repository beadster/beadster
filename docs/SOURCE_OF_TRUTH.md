# source of truth in beadster

understanding what's saved where and what gets committed to git

## beads core architecture

beads uses JSONL as source of truth with SQLite as query cache:

```
.beads/
├── issues.jsonl      ← SOURCE OF TRUTH (complete issue snapshots)
└── beads.db          ← CACHE (for fast queries)
```

### JSONL = source of truth

single `issues.jsonl` file contains one complete issue per line:

```json
{"id":"bd-1","title":"Fix bug","status":"open","priority":2,"created_at":"2025-10-17T22:19:13Z","updated_at":"2025-10-17T22:19:13Z"}
{"id":"bd-2","title":"Add feature","status":"closed","priority":1,"created_at":"2025-10-18T10:42:48Z","updated_at":"2025-10-18T11:30:00Z","closed_at":"2025-10-18T11:30:00Z"}
```

each line is a complete issue snapshot (not events). when issue is updated, the entire line is replaced.

### SQLite = query cache

`beads.db` is a cache for fast queries:
- bd CLI auto-imports from JSONL when JSONL is newer
- bd CLI auto-exports to JSONL after create/update/close operations
- both files stay in sync automatically

**NEVER committed to git** - always regenerated from JSONL.

## how bd CLI keeps files in sync

bd CLI has automatic sync flags (enabled by default):
- `--no-auto-flush` - disable automatic JSONL export after CRUD operations
- `--no-auto-import` - disable automatic JSONL import when JSONL is newer than DB

default behavior (both enabled):
1. `bd create "Fix bug"` writes to SQLite AND exports to JSONL
2. `bd close bd-1` updates SQLite AND exports to JSONL
3. `bd list` auto-imports from JSONL if it's newer than DB

this means both files stay in sync automatically.

## beadster macOS app approach

macOS app is sandboxed and CANNOT execute bd CLI commands.

### reading (hybrid approach)

1. reads baseline from `.beads/beadster.db` (bd CLI's SQLite cache)
2. checks max `updated_at` timestamp from SQLite
3. reads JSONL line-by-line for newer issues (updated_at > max)
4. merges SQLite + JSONL changes into in-memory state

this ensures app sees latest changes even if bd database is stale.

### writing

writes directly to `.beads/issues.jsonl` only:
- maintains source of truth
- updates in-memory `IssueStore.issues` array immediately
- does NOT update bd's SQLite database (sandboxed - cannot call bd CLI)
- bd CLI will auto-import changes on next `bd list` run

### why not write to SQLite?

macOS app cannot rebuild bd's `.beads/beadster.db` because:
- app is sandboxed (cannot execute bd CLI)
- SQLite schema is owned by bd CLI
- attempting to write could break bd CLI compatibility

instead: write to JSONL (source of truth), let bd CLI rebuild its cache.

### sync behavior

- bd CLI auto-imports JSONL when newer than DB
- macOS app reads hybrid (SQLite + JSONL merge)
- both stay in sync through JSONL as shared source of truth

## beadster cloud sync extension

beadster adds cloud sync metadata in `beads.db` without touching JSONL files.

### beadster_sync table

lives in same `beads.db` but stores separate metadata:

```sql
CREATE TABLE beadster_sync (
  issue_id TEXT PRIMARY KEY,
  cloud_id TEXT NOT NULL,
  synced_at INTEGER NOT NULL,
  cloud_updated_at INTEGER,
  local_updated_at INTEGER,
  sync_status TEXT DEFAULT 'synced',
  last_error TEXT,
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);
```

### why not in JSONL?

cloud sync metadata should NOT go in issues JSONL because:
- per-machine state (each device has different sync state)
- not portable (cloud IDs only matter for sync, not issue tracking)
- ephemeral (can be rebuilt by re-syncing)
- beads purity (beads should work without cloud)

### beadster_source table

source-level sync metadata:

```sql
CREATE TABLE beadster_source (
  id TEXT PRIMARY KEY DEFAULT '1',
  source_id TEXT,
  last_full_sync INTEGER,
  last_pull INTEGER,
  last_push INTEGER
);
```

## what gets committed to git

```
git tracked:
✅ .beads/issues.jsonl       (source of truth)
✅ .beads/config.toml        (if exists)

git ignored:
❌ .beads/beads.db           (cache + sync metadata)
```

## verified behavior

tested with beadster project:
- `bd create "test bd behavior"` - both `.db` and `.jsonl` updated simultaneously
- `bd close beadster-88` - both files updated simultaneously
- `bd show beadster-88` from database matched JSONL content exactly
- modification timestamps confirmed both files update together

## multi-device sync flow

when using beadster cloud sync across multiple machines:

```
Machine A:
1. bd create "Fix bug"        → writes to issues.jsonl
2. git add + commit + push    → JSONL to git
3. sync daemon runs           → pushes to cloud, gets cloud_id
4. writes to beadster_sync    → stores mapping (bd-1 → cloud_id)
   (NOT committed to git)

Machine B:
5. git pull                   → gets issues.jsonl
6. bd list                    → auto-imports JSONL to beads.db
7. sync daemon runs           → pulls from cloud
8. finds cloud issue          → matches by source_id + beads_id
9. writes to beadster_sync    → stores mapping (bd-1 → cloud_id)

Both machines now have:
- Same JSONL (from git)
- Same issues table (rebuilt from JSONL by bd)
- Same beadster_sync mappings (from cloud sync)
```

## why this works

1. bd CLI reads from database (fast queries)
2. bd CLI writes to both database AND JSONL (auto-flush)
3. macOS app reads from database (fast queries)
4. macOS app writes to JSONL (source of truth)
5. bd CLI auto-imports JSONL changes when JSONL is newer
6. git workflow uses JSONL for collaboration
7. cloud sync uses beadster_sync table for metadata
8. bd CLI, macOS app, and cloud sync can coexist without conflicts

## summary

### source of truth layers

1. `issues.jsonl` - ultimate source of truth for issue data, committed to git
2. `beads.db/issues` - query cache, never committed, auto-rebuilt from JSONL by bd CLI
3. `beads.db/beadster_sync` - cloud sync metadata, never committed, rebuilt from cloud
4. cloud database - aggregation layer for multi-device sync

### data flow

```
bd CLI:
  bd create/update/close → writes SQLite + exports JSONL
  bd list/show          → auto-imports JSONL if newer → reads SQLite

macOS app:
  read operations       → reads SQLite baseline + JSONL delta (hybrid merge)
  write operations      → writes JSONL + updates in-memory array

cloud sync:
  sync daemon           → reads SQLite (issues + beadster_sync tables)
                        → syncs with cloud API
                        → writes to beadster_sync table

git workflow:
  git commit/push       → commits JSONL only
  git pull              → receives JSONL
  bd list               → auto-imports JSONL to SQLite
```

all components (bd CLI, macOS app, cloud sync) stay in sync through JSONL as shared source of truth.
