# source of truth in beadster

understanding what's saved where and what gets committed to git

## beads core architecture

beads uses event sourcing with JSONL as source of truth:

```
.beads/
├── issues/
│   ├── bd-1.jsonl    ← SOURCE OF TRUTH (append-only event log)
│   ├── bd-2.jsonl
│   └── bd-3.jsonl
└── beads.db          ← CACHE (rebuilt from JSONL)
```

### JSONL = event log

each JSONL file is an append-only log of events:

```json
// .beads/issues/bd-1.jsonl
{"type":"create","time":1234567890,"user":"anton","title":"Fix bug","body":"Details here"}
{"type":"update","time":1234567895,"user":"anton","status":"closed"}
{"type":"comment","time":1234567900,"user":"anton","text":"Fixed in commit abc123"}
```

beads reads these events and builds SQLite database for fast queries.

### SQLite = query cache

`beads.db` is rebuilt whenever:
- beads detects JSONL is newer than DB
- beads runs any command
- JSONL is modified

**NEVER committed to git** - always regenerated from JSONL.

## beadster extension: separate metadata

beadster adds cloud sync metadata WITHOUT touching beads JSONL files.

### what beadster adds

```
.beads/
├── issues/              (beads - git tracked)
│   ├── bd-1.jsonl
│   └── bd-2.jsonl
│
├── beads.db             (beads cache - git ignored)
│   ├── issues           (rebuilt from JSONL)
│   ├── dependencies     (rebuilt from JSONL)
│   └── beadster_sync    (beadster extension table)
│
└── .gitignore
    beads.db
```

**beadster_sync table** lives in same `beads.db` but stores separate metadata:

```sql
CREATE TABLE beadster_sync (
  issue_id TEXT PRIMARY KEY,
  cloud_id TEXT,
  synced_at INTEGER,
  cloud_updated_at INTEGER,
  FOREIGN KEY (issue_id) REFERENCES issues(id)
);
```

### why not in JSONL?

cloud sync metadata should NOT go in issues JSONL because:

1. **per-machine state** - each device has different sync state
2. **not portable** - cloud IDs only matter for sync, not issue tracking
3. **ephemeral** - can be rebuilt by re-syncing
4. **beads purity** - beads should work without cloud

## what gets committed to git

```
git tracked:
✅ .beads/issues/*.jsonl     (beads event logs)
✅ .beads/config.toml        (beads config)

git ignored:
❌ .beads/beads.db           (cache, rebuilt from JSONL)
❌ .beads/beadster/          (if we add separate files)
```

## what gets rebuilt

when you clone repo or pull changes:

```bash
git pull                    # gets JSONL files
bd list                     # beads rebuilds beads.db from JSONL
                           # beadster_sync table starts empty

beadster-sync              # sync daemon runs
                           # reads issues from beads tables
                           # syncs with cloud
                           # populates beadster_sync table
```

each machine builds its own `beadster_sync` state through syncing.

## cloud IDs: not in git

**example flow:**

```
Desktop A:
1. bd create "Fix bug"        → writes .beads/issues/bd-1.jsonl
2. git add + commit + push    → JSONL to git
3. sync daemon runs           → pushes to cloud, gets cloud_id "01HQXYZ"
4. writes to beadster_sync    → stores mapping (bd-1 → 01HQXYZ)
   (NOT committed to git)

Desktop B:
5. git pull                   → gets .beads/issues/bd-1.jsonl
6. bd list                    → rebuilds beads.db (no sync data yet)
7. sync daemon runs           → pulls from cloud
8. finds cloud issue 01HQXYZ  → matches bd-1 by (source_id, beads_id)
9. writes to beadster_sync    → stores mapping (bd-1 → 01HQXYZ)

Both machines now have:
- Same JSONL (from git)
- Same beads tables (rebuilt from JSONL)
- Same beadster_sync mappings (from cloud sync)
```

## schema architecture

### beads core (rebuilt from JSONL)

```sql
CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  title TEXT,
  status TEXT,
  created_at DATETIME,
  updated_at DATETIME
);

CREATE TABLE dependencies (
  issue_id TEXT,
  depends_on_id TEXT,
  type TEXT
);
```

### beadster extension (persistent across rebuilds)

```sql
CREATE TABLE beadster_sync (
  issue_id TEXT PRIMARY KEY,
  cloud_id TEXT NOT NULL,
  synced_at INTEGER,
  cloud_updated_at INTEGER,
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);
```

**important:** when beads rebuilds from JSONL, it should:
- drop and recreate `issues`, `dependencies` tables
- preserve `beadster_*` extension tables

## conflict resolution

when both machines modify same issue:

1. **local change:**
   - bd update bd-1 --title="New title"
   - writes event to bd-1.jsonl
   - git commit + push

2. **cloud change:**
   - different machine updates cloud
   - sync daemon pulls change
   - applies via bd update (writes to JSONL)

3. **conflict detection:**
   - beadster_sync table tracks last sync timestamps
   - can detect if both local and cloud changed
   - resolution: last-write-wins (for now)

## summary

### source of truth layers

1. **issues.jsonl** - ultimate source of truth for issue data
2. **beads.db** - query cache, rebuilt from JSONL
3. **beadster_sync** - sync metadata, rebuilt from cloud
4. **cloud** - aggregation layer for multi-device sync

### commit rules

```
git commit:
  ✅ JSONL event logs (beads data)
  ❌ SQLite database (cache)
  ❌ sync metadata (per-machine)

cloud sync:
  ✅ issue data (from beads tables)
  ✅ cloud IDs (generated by cloud)
  ✅ sync timestamps (track state)
```

### data flow

```
Developer action     → JSONL event     → git commit
                        ↓
Beads rebuild        ← JSONL read      ← git pull
                        ↓
Sync daemon          → Cloud API       → Cloud DB
                        ↓                  ↓
beadster_sync table  ← Cloud response  ← Cloud DB
```

beads stays pure, cloud stays separate, both work together.
