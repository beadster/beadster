# beadster_sync table implementation guide

complete guide for implementing cloud sync metadata in local beads.db

## overview

this document explains how beadster extends beads with cloud sync capabilities using the beadster_sync extension table.

**key principle:** beads stays pure (JSONL source of truth), beadster adds cloud orchestration layer

## architecture

```
.beads/
├── issues/              (beads - git tracked)
│   ├── bd-1.jsonl      SOURCE OF TRUTH (append-only events)
│   └── bd-2.jsonl
│
├── beads.db            (beads cache - git ignored, rebuilt from JSONL)
│   ├── issues          (rebuilt by beads from JSONL)
│   ├── dependencies    (rebuilt by beads from JSONL)
│   ├── events          (rebuilt by beads from JSONL)
│   │
│   └── beadster_sync   (extension - built by sync daemon)
│
└── .gitignore
    beads.db            # NEVER commit db file
```

## source of truth layers

| layer | file | committed to git | rebuilt from | purpose |
|-------|------|------------------|--------------|---------|
| 1. beads events | `issues/*.jsonl` | ✅ YES | n/a | ultimate source of truth |
| 2. beads cache | `beads.db` (issues table) | ❌ NO | JSONL | fast queries |
| 3. sync metadata | `beads.db` (beadster_sync table) | ❌ NO | cloud API | cloud ID mapping |
| 4. cloud | D1 database | ❌ NO | local push | multi-device aggregation |

## schema

### beadster_sync table

```sql
-- in .beads/beads.db (same file as beads tables)

CREATE TABLE IF NOT EXISTS beadster_sync (
  issue_id TEXT PRIMARY KEY,              -- bd-1, bd-2 (local beads ID)
  cloud_id TEXT NOT NULL,                 -- 01HQXYZ... (ULID from cloud)
  synced_at INTEGER NOT NULL,             -- unix timestamp of last sync
  cloud_updated_at INTEGER,               -- cloud's updated_at at last sync
  local_updated_at INTEGER,               -- local's updated_at at last sync
  sync_status TEXT DEFAULT 'synced',      -- 'synced', 'pending', 'conflict'
  last_error TEXT,                        -- error message if sync failed
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_beadster_sync_cloud_id
  ON beadster_sync(cloud_id);
CREATE INDEX IF NOT EXISTS idx_beadster_sync_status
  ON beadster_sync(sync_status);
```

### beadster_source table

```sql
-- source-level metadata

CREATE TABLE IF NOT EXISTS beadster_source (
  id TEXT PRIMARY KEY DEFAULT '1',       -- singleton row
  source_id TEXT,                        -- cloud source ID (e.g., src-abc123)
  last_full_sync INTEGER,                -- last complete sync timestamp
  last_pull INTEGER,                     -- last successful pull timestamp
  last_push INTEGER                      -- last successful push timestamp
);
```

## use cases

### use case 1: first sync (empty beadster_sync table)

**scenario:** fresh clone of repo, never synced before

```
local state:
.beads/
├── issues/bd-1.jsonl    (from git)
├── issues/bd-2.jsonl    (from git)
└── beads.db
    ├── issues (bd-1, bd-2)     rebuilt from JSONL
    └── beadster_sync           EMPTY

cloud state:
- source: myapp (src-123)
- issues:
  - cloud-abc (source=src-123, beads_id=bd-1, title="Fix bug")
  - cloud-def (source=src-123, beads_id=bd-2, title="Add feature")
```

**sync flow:**

```swift
// 1. init extension tables if needed
let ext = BeadsterExtension(beadsDir: projectPath)
try ext.initialize()

// 2. get source ID from cloud (or create)
let sourceId = try await registerSource(name: "myapp", path: projectPath)
try ext.updateSourceMeta(sourceId: sourceId)

// 3. pull all issues from cloud (since=0 for first sync)
let since = try ext.getLastPull() ?? 0  // 0 = first time
let cloudIssues = try await api.pull(sourceId: sourceId, since: since)

// cloudIssues = [
//   { id: "cloud-abc", beads_id: "bd-1", title: "Fix bug", updated_at: 1000 },
//   { id: "cloud-def", beads_id: "bd-2", title: "Add feature", updated_at: 2000 }
// ]

// 4. for each cloud issue, record mapping
for cloudIssue in cloudIssues {
    let localIssue = try db.getIssue(id: cloudIssue.beadsId)

    if let local = localIssue {
        // record cloud ID mapping
        try ext.recordSync(
            issueId: cloudIssue.beadsId,      // bd-1
            cloudId: cloudIssue.id,            // cloud-abc
            localUpdatedAt: local.updatedAt,
            cloudUpdatedAt: cloudIssue.updatedAt
        )
    }
}

// 5. update source metadata
try ext.updateSourceMeta(sourceId: sourceId, lastPull: Date.now())
```

**result:**

```
beadster_sync table now has:
bd-1 | cloud-abc | 1234567890 | 1000 | 1000 | synced
bd-2 | cloud-def | 1234567890 | 2000 | 2000 | synced

beadster_source table:
'1' | src-123 | null | 1234567890 | null
```

### use case 2: incremental push (local changes)

**scenario:** user updates issue locally

```
user action:
$ bd update bd-1 --status=closed

local state:
.beads/issues/bd-1.jsonl    (new event appended)
beads.db:
  issues (bd-1.updated_at = 3000)
  beadster_sync (bd-1: local_updated_at = 1000)
```

**detection:**

```swift
// sync daemon detects change
let unsyncedIds = try ext.getUnsyncedIssues()
// returns ["bd-1"] because local_updated_at (1000) < issues.updated_at (3000)
```

**push:**

```swift
// 1. get only unsynced issues
let issues = try db.getIssues(ids: unsyncedIds)

// 2. push to cloud
let result = try await api.push(sourceId: sourceId, issues: issues)
// result = { synced: 1 }

// 3. update sync metadata
for issue in issues {
    let cloudId = try ext.getCloudId(issueId: issue.id) ?? issue.id
    try ext.recordSync(
        issueId: issue.id,
        cloudId: cloudId,
        localUpdatedAt: issue.updatedAt,     // 3000
        cloudUpdatedAt: Date.now()
    )
}

// 4. update source metadata
try ext.updateSourceMeta(sourceId: sourceId, lastPush: Date.now())
```

**result:**

```
beadster_sync:
bd-1 | cloud-abc | 1234567895 | 3000 | 3000 | synced
```

### use case 3: incremental pull (cloud changes)

**scenario:** another device updated cloud

```
cloud state changed:
- cloud-abc updated_at changed: 2000 → 4000

local state:
beadster_sync:
  bd-1 | cloud-abc | ... | cloud_updated_at=2000 | ...
beadster_source:
  last_pull = 3000
```

**pull:**

```swift
// 1. get last pull timestamp
let since = try ext.getLastPull() ?? 0  // 3000

// 2. pull changes since last sync
let changes = try await api.pull(sourceId: sourceId, since: since)
// returns only issues updated after timestamp 3000

// changes = [
//   { id: "cloud-abc", beads_id: "bd-1", status: "closed", updated_at: 4000 }
// ]

// 3. apply each change
for cloudIssue in changes {
    // check if exists locally
    let exists = try db.issueExists(beadsId: cloudIssue.beadsId)

    if exists {
        // update via bd CLI (writes to JSONL)
        try await applyChange(issue: cloudIssue, projectPath: path)

        // update sync metadata
        try ext.recordSync(
            issueId: cloudIssue.beadsId,
            cloudId: cloudIssue.id,
            localUpdatedAt: cloudIssue.updatedAt,
            cloudUpdatedAt: cloudIssue.updatedAt
        )
    } else {
        // skip new issues from cloud (would create ID collision)
        print("skipping new cloud issue: \(cloudIssue.beadsId)")
    }
}

// 4. update source metadata
try ext.updateSourceMeta(sourceId: sourceId, lastPull: Date.now())
```

**applyChange implementation:**

```swift
func applyChange(issue: Issue, projectPath: String) async throws {
    let escapedTitle = issue.title.replacingOccurrences(of: "\"", with: "\\\"")

    let command = """
    cd "\(projectPath)" && bd update \(issue.beadsId) \
    --title="\(escapedTitle)" \
    --status=\(issue.status) \
    --priority=\(issue.priority)
    """

    // execute bd command (writes to JSONL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    try process.run()
    process.waitUntilExit()

    // beads will auto-rebuild db from JSONL
}
```

### use case 4: conflict detection

**scenario:** both local and cloud modified same issue

```
initial state (after last sync):
beadster_sync:
  bd-1 | cloud-abc | synced_at=1000 | cloud_updated_at=2000 | local_updated_at=2000

local change:
$ bd update bd-1 --title="New title"
→ local updated_at = 5000

cloud change (from other device):
→ cloud updated_at = 6000

current state:
local: bd-1.updated_at = 5000
cloud: cloud-abc.updated_at = 6000
beadster_sync: local_updated_at=2000, cloud_updated_at=2000
```

**detection:**

```swift
func detectConflicts() throws -> [(Issue, CloudIssue)] {
    let conflicts: [(Issue, CloudIssue)] = []

    // get issues with potential conflicts
    let query = """
    SELECT i.*, s.cloud_id, s.local_updated_at, s.cloud_updated_at
    FROM issues i
    JOIN beadster_sync s ON s.issue_id = i.id
    WHERE i.updated_at > s.local_updated_at
    """

    let localChanges = db.exec(query)

    for local in localChanges {
        // fetch cloud version
        let cloudIssue = try await api.getIssue(cloudId: local.cloudId)

        // check if cloud also changed
        if cloudIssue.updatedAt > local.cloudUpdatedAt {
            // CONFLICT! both changed
            conflicts.append((local, cloudIssue))
        }
    }

    return conflicts
}
```

**resolution (last-write-wins for POC):**

```swift
func resolveConflict(local: Issue, cloud: CloudIssue) async throws {
    if cloud.updatedAt > local.updatedAt {
        // cloud wins - apply cloud changes
        try await applyChange(issue: cloud, projectPath: path)
    } else {
        // local wins - push to cloud
        try await api.push(sourceId: sourceId, issues: [local])
    }

    // update sync metadata with winner
    try ext.recordSync(
        issueId: local.id,
        cloudId: cloud.id,
        localUpdatedAt: max(local.updatedAt, cloud.updatedAt),
        cloudUpdatedAt: max(local.updatedAt, cloud.updatedAt)
    )
}
```

### use case 5: new machine discovers cloud IDs

**scenario:** clone repo on machine B

```
machine A (original):
.beads/
├── issues/bd-1.jsonl
└── beads.db
    └── beadster_sync
        bd-1 | cloud-abc | synced

git push
→ only bd-1.jsonl goes to git

machine B (clone):
git pull
.beads/
├── issues/bd-1.jsonl    (from git)
└── beads.db
    ├── issues (bd-1)    (rebuilt from JSONL by beads)
    └── beadster_sync    (EMPTY - not in git!)
```

**discovery through cloud API:**

```swift
// machine B first sync
let since = try ext.getLastPull() ?? 0  // 0 = never synced

// pull all issues for this source
let cloudIssues = try await api.pull(sourceId: "src-123", since: 0)
// [{ id: "cloud-abc", beads_id: "bd-1", ... }]

// cloud API matches by (source_id, beads_id)
// returns cloud_id for each local beads_id

for cloudIssue in cloudIssues {
    // find matching local issue
    let localIssue = try db.getIssue(id: cloudIssue.beadsId)

    if let local = localIssue {
        // store discovered mapping
        try ext.recordSync(
            issueId: "bd-1",           // local ID (from JSONL)
            cloudId: "cloud-abc",       // discovered from cloud
            localUpdatedAt: local.updatedAt,
            cloudUpdatedAt: cloudIssue.updatedAt
        )
    }
}
```

**cloud schema enables this:**

```sql
-- cloud DB has both IDs
CREATE TABLE issues (
  id TEXT PRIMARY KEY,                -- cloud-abc (global ULID)
  source_id TEXT NOT NULL,            -- src-123
  beads_id TEXT NOT NULL,             -- bd-1 (local ID from beads)
  title TEXT,
  -- ...
  UNIQUE (source_id, beads_id)        -- enables lookup!
);

-- query to match local ID to cloud ID:
SELECT id FROM issues
WHERE source_id = 'src-123' AND beads_id = 'bd-1'
-- returns: cloud-abc
```

### use case 6: ID collision prevention

**scenario:** web creates bd-5, desktop also creates bd-5 locally

```
timeline:
1. desktop A: has bd-1, bd-2, bd-3, bd-4 (synced)
2. web user: creates issue for source "myapp"
   → cloud assigns beads_id = "bd-5"
3. desktop A (offline): creates bd-5 locally (different issue!)
4. desktop A: comes online, syncs
```

**prevention using source_sequences:**

```sql
-- cloud tracks next ID per source
CREATE TABLE source_sequences (
  source_id TEXT PRIMARY KEY,
  next_beads_id INTEGER NOT NULL DEFAULT 1
);

-- when web creates issue:
UPDATE source_sequences
SET next_beads_id = next_beads_id + 1
WHERE source_id = 'src-123'
RETURNING next_beads_id - 1 as beads_id_num
-- returns: 5

INSERT INTO issues (id, source_id, beads_id, ...)
VALUES ('cloud-xyz', 'src-123', 'bd-5', ...)
```

**collision detection on sync:**

```swift
// desktop A pushes bd-5
try await api.push(sourceId: "src-123", issues: [localBd5])

// cloud API checks for collision:
let existing = await db.prepare(`
  SELECT id, created_by_device_id FROM issues
  WHERE source_id = ? AND beads_id = ?
`).bind(sourceId, "bd-5").first()

if (existing && existing.id != localBd5.cloudId) {
  // COLLISION DETECTED!

  // check if cloud bd-5 seen by real clients
  let tracking = await db.prepare(`
    SELECT client FROM device_issue_tracking
    WHERE issue_id = ?
  `).bind(existing.id).all()

  let seenByRealClient = tracking.some(t =>
    ['macos', 'ios', 'cli'].includes(t.client)
  )

  if (!seenByRealClient) {
    // web-only, safe to renumber cloud bd-5 → bd-6
    await renumberCloudIssue(existing.id, "bd-6")
    // desktop's bd-5 wins
  } else {
    // real client saw it, must renumber desktop bd-5
    return {
      error: "collision",
      renumber: { from: "bd-5", to: "bd-6" }
    }
  }
}
```

**desktop handles renumber:**

```swift
if let renumber = result.renumber {
    // renumber local issue via bd
    try exec(`bd renumber \(renumber.from) \(renumber.to)`)

    // update sync metadata with new ID
    try ext.recordSync(
        issueId: renumber.to,
        cloudId: result.cloudId,
        localUpdatedAt: issue.updatedAt,
        cloudUpdatedAt: Date.now()
    )
}
```

## implementation checklist

### 1. create BeadsterExtension class

- [ ] initialize() - create tables if not exist
- [ ] getSyncInfo(issueId) - get sync metadata for issue
- [ ] recordSync(...) - upsert sync metadata after push/pull
- [ ] getCloudId(issueId) - lookup cloud ID for local ID
- [ ] getUnsyncedIssues() - find issues needing push
- [ ] updateSourceMeta(...) - update source-level timestamps
- [ ] getLastPull() - get last pull timestamp for incremental sync

### 2. update BeadsDatabase class

- [ ] change path from `beads.db` → `beads.db`
- [ ] read from beads core tables (issues, dependencies)
- [ ] add method to get specific issues by IDs
- [ ] add method to check if issue exists

### 3. update SyncDaemon class

- [ ] initialize extension on startup
- [ ] use incremental push (only unsynced issues)
- [ ] use incremental pull (only changes since last_pull)
- [ ] record sync metadata after each operation
- [ ] detect and handle conflicts

### 4. cloud API updates

- [ ] /api/sync/pull supports since parameter
- [ ] /api/sync/push handles collisions
- [ ] /api/sources/:id/sequence for ID management
- [ ] /api/device-tracking for conflict resolution

### 5. testing

- [ ] test first sync (empty beadster_sync)
- [ ] test incremental push
- [ ] test incremental pull
- [ ] test conflict detection
- [ ] test new machine discovery
- [ ] test ID collision prevention

## performance comparison

**before (current implementation):**

```swift
// every sync:
let allIssues = db.getAllIssues()          // 100 issues
api.push(issues: allIssues)                // uploads 100 issues (~1MB)
let allCloudIssues = api.pull(sourceId)    // downloads 100 issues (~1MB)
```

**after (with beadster_sync):**

```swift
// most syncs:
let unsyncedIds = ext.getUnsyncedIssues()  // 2 issues
let issues = db.getIssues(ids: unsyncedIds)
api.push(issues: issues)                    // uploads 2 issues (~20KB)

let since = ext.getLastPull()
let changes = api.pull(sourceId, since)     // downloads 1 issue (~10KB)
```

**speedup:** 10-100x faster, especially with many issues

## key insights

1. **JSONL is source of truth** - beadster_sync is cache, can be rebuilt
2. **each machine builds its own sync state** - through cloud API
3. **cloud enables discovery** - maps (source_id, beads_id) → cloud_id
4. **incremental sync** - only transfer what changed
5. **conflict detection** - compare timestamps in sync metadata
6. **ID collision prevention** - use source_sequences + device_issue_tracking

## migration path

1. **deploy cloud API changes** (add since parameter to /pull)
2. **deploy BeadsterExtension** code to sync daemons
3. **first run** - sync daemons create extension tables automatically
4. **first sync** - builds initial beadster_sync from cloud (since=0)
5. **ongoing** - incremental syncs using timestamps

no data migration needed - tables created on demand!
