# implementation ready - beadster_sync extension

all documentation complete and ready to start implementation

## documentation created/updated

### new docs

1. **SOURCE_OF_TRUTH.md** - explains what gets committed to git vs rebuilt
   - JSONL files are source of truth (git tracked)
   - beads.db is cache (git ignored, rebuilt from JSONL)
   - beadster_sync table is per-machine metadata (git ignored, built from cloud sync)

2. **BEADSTER_SYNC_IMPLEMENTATION.md** - complete implementation guide
   - schema for beadster_sync and beadster_source tables
   - 6 detailed use cases with code examples
   - implementation checklist
   - performance comparison (10-100x faster with incremental sync)

### updated docs

1. **README.md** - fixed architecture diagram
   - now mentions JSONL as source of truth
   - clarified beads.db is rebuilt from JSONL
   - added reference to SOURCE_OF_TRUTH.md

2. **AUTO_SETUP.md** - fixed database references
   - clarified beads.db vs beadster.json

3. **EXTENDING_BEADS.md** - added emphasis on JSONL source of truth
   - clarified beads.db is CACHE, not source of truth

4. **IDENTITY_AND_SHARING.md** - clarified extension table location
   - beadster_context table in .beads/beads.db

5. **src/sync/README.md** - updated how it works section
   - incremental sync explanation
   - reference to implementation guide

## code skeleton created

**src/sync/Sources/BeadsterExtension.swift** - foundation class with:
- initialize() - create extension tables
- getSyncInfo() - get sync metadata for issue
- recordSync() - record sync after push/pull
- getCloudId() - lookup cloud ID for local issue
- getUnsyncedIssues() - find issues needing push
- updateSourceMeta() - track source-level timestamps
- getLastPull() - for incremental pull

## ready to implement

next steps:

1. **fix BeadsDatabase.swift** (both CLI and macOS app)
   - change from `beads.db` → `beads.db`
   - read from beads core tables (issues, dependencies, events)
   - add methods: getIssues(ids:), issueExists()

2. **update SyncDaemon.swift** (both CLI and macOS app)
   - initialize BeadsterExtension on startup
   - use incremental push (only getUnsyncedIssues())
   - use incremental pull (pass since timestamp)
   - recordSync() after each push/pull

3. **test end-to-end**
   - first sync (empty beadster_sync)
   - incremental push (local changes)
   - incremental pull (cloud changes)
   - new machine discovery
   - conflict detection

4. **cloud API enhancements** (optional, works with current API)
   - add conflict detection logic
   - add source_sequences table for ID collision prevention

## key decisions made

1. ✅ **use beads.db** (not separate beads.db) - follows beads extension pattern
2. ✅ **cloud IDs NOT in JSONL** - keeps beads pure, cloud is separate layer
3. ✅ **each machine builds its own sync state** - through cloud API discovery
4. ✅ **incremental sync** - only transfer what changed (10-100x faster)
5. ✅ **extension tables survive beads rebuilds** - SQLite tables persist even when beads recreates issues table

## what doesn't get committed to git

```
.beads/
├── issues/*.jsonl    ✅ GIT (source of truth)
├── beads.db          ❌ GIT (cache + extension tables)
└── beadster.json     ❌ GIT (local config)
```

## what gets rebuilt vs discovered

| data | source | rebuilt from |
|------|--------|--------------|
| beads issues table | beads | JSONL files |
| beadster_sync table | beadster | cloud API (first sync with since=0) |
| cloud ID mappings | beadster | cloud API query (source_id, beads_id) → cloud_id |

## approval confirmed

user approved:
- schema design
- extension table approach (in beads.db, not separate file)
- incremental sync strategy
- fixing both sync daemons (CLI and macOS app)

ready to start implementation!
