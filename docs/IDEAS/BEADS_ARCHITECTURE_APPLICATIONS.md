# beads architecture applications to other domains

analysis of how beads architecture (JSONL + SQLite + git/cloud) could apply to other local-first applications

## core architectural patterns in beads

key insight: JSONL as source of truth + SQLite as rebuildable cache + git/cloud for sync

components:
- JSONL = source of truth (human-readable, git-friendly, portable, append-only or snapshot-per-line)
- SQLite = query cache (fast searches, complex queries, full-text search, can be deleted and rebuilt)
- git layer (JSONL git-tracked, free sync, version control, merge conflicts handleable)
- cloud extension (adds real-time sync without touching core architecture)
- multi-client strategy (CLI writes JSONL+SQLite, sandboxed apps write JSONL only, automatic rebuilds)
- conflict resolution (timestamp-based, desktop wins, ID collision handling via device tracking)

## applications that work excellently with this architecture

### 1. local-first notes system

```
.notes/
├── notes.jsonl          source of truth
├── notes.db             cache (FTS, tags, search)
└── attachments/         images, PDFs
```

why perfect:
- notes are mostly append/update (low conflict rate)
- markdown content serializes to JSON easily
- SQLite FTS for full-text search
- git gives version history for free
- cloud sync for mobile access
- CLI for scripting, GUI for rich editing

advantages over obsidian/bear:
- git sync (free, private, your own repo)
- portable (plain JSONL files)
- CLI automation (grep, sed, scripting)
- self-hostable cloud sync
- fast SQLite search

trade-offs:
- no real-time collaboration (but conflicts rare in personal notes)
- initial implementation effort
- mobile apps need native JSONL support

### 2. local-first bookmarks/research manager

```
.bookmarks/
├── bookmarks.jsonl      {"id":"bm-1","url":"...","tags":["dev","rust"],"archived_html":"..."}
└── bookmarks.db         search, tags, dead-link detection
```

perfect for:
- developers who save hundreds of links
- archive.org integration (save page snapshots)
- browser extensions write to JSONL
- full-text search of archived content
- git history shows when you saved what

### 3. local-first time tracking

```
.timetrack/
├── entries.jsonl        append-only time entries
└── timetrack.db         aggregations, reports, invoicing
```

why brilliant:
- time entries are immutable events (perfect for append-only JSONL)
- SQLite for complex reports (hours per project, week, client)
- git log = complete audit trail
- cloud sync for mobile timer
- multiple clients (CLI, menubar app, mobile widget)

### 4. local-first expenses/receipts

```
.expenses/
├── expenses.jsonl       {"id":"exp-1","amount":50,"category":"food","receipt":"receipts/img.jpg"}
├── receipts/            actual files
└── expenses.db          reports, tax calculations
```

advantages:
- immutable financial records (JSONL = audit trail)
- git history for tax audits
- photo receipts on mobile sync to desktop
- SQLite for complex tax reports
- everything backed up automatically

### 5. local-first habit tracker

```
.habits/
├── habits.jsonl         habit definitions
├── logs.jsonl           completion events (append-only)
└── habits.db            streaks, statistics, graphs
```

perfect fit:
- logs are pure append-only events
- SQLite calculates streaks, patterns
- git shows habit evolution over time
- cloud sync for logging anywhere
- privacy (health data stays local)

### 6. local-first personal CRM

```
.contacts/
├── contacts.jsonl       people, companies
├── interactions.jsonl   meetings, emails, notes (append-only)
└── contacts.db          search, relationship graphs
```

why powerful:
- interaction history is append-only
- git = complete relationship timeline
- privacy (your network stays local)
- SQLite for "who haven't I talked to in 6 months"
- cloud sync for mobile access

### 7. local-first workout logger

```
.workouts/
├── workouts.jsonl       {"date":"2025-10-20","exercises":[{"name":"squat","sets":3,"reps":10}]}
├── exercises.jsonl      exercise definitions
└── workouts.db          progress tracking, PRs, graphs
```

use cases:
- track strength training progress
- calculate PRs and volume
- graph progress over time
- export for coaching

### 8. local-first reading list

```
.reading/
├── articles.jsonl       {"url":"...","status":"reading","progress":45}
├── archive/             saved HTML/PDF
└── reading.db           search, read-it-later queue
```

features:
- save articles for later
- archive full HTML/PDF
- track reading progress
- full-text search archive

## what makes an app suitable for this architecture

### perfect fits

- personal/small team (not millions of concurrent users)
- structured data (JSON-serializable)
- mostly append/update (not high-frequency edits to same record)
- benefits from git (version control, audit trail valuable)
- offline-first desirable (should work without internet)
- multiple clients needed (CLI + GUI + mobile)
- privacy-focused (local-first, optional cloud)
- developer-friendly (power users who appreciate CLI)

### poor fits

- real-time collaboration (google docs - too many conflicts)
- massive datasets (millions of records - JSONL parsing becomes slow)
- high-frequency updates (stock tickers, gaming state - too much churn)
- primarily binary data (photo library - though metadata works great)
- complex graph queries (social networks - use graph DB)
- requires strong ACID (banking transactions - use PostgreSQL)

## architecture strengths

- simplicity: text files + SQLite = understandable, debuggable, no magic
- resilience: SQLite corrupted? delete it, rebuild from JSONL in seconds
- git-native: diffs, merges, history, branches all work naturally
- debuggability: `cat notes.jsonl | grep "bug"` - inspect data anytime
- portability: works everywhere SQLite works (basically everywhere)
- extensibility: cloud sync bolts on without changing core (like beadster does)
- multi-client: same data accessible from CLI, GUI, mobile, web
- privacy: data local by default, you control cloud
- future-proof: JSON and SQLite will exist in 50 years
- incremental sync: only transfer what changed (very efficient)

## architecture weaknesses and mitigations

scale ceiling:
- issue: 100k+ records makes JSONL parsing slow
- mitigation: partition data, archive old data, lazy loading

write concurrency:
- issue: JSONL needs file locking
- mitigation: single writer process (like beads does)

real-time limits:
- issue: poll-based, not WebSocket instant
- mitigation: add WebSocket notifications in cloud layer

binary data:
- issue: JSONL not suitable for images/videos
- mitigation: content-addressed storage like git (store files separately)

schema evolution:
- issue: must handle old JSON formats
- mitigation: version field in each record, migration scripts

mobile complexity:
- issue: sandboxing prevents CLI execution
- mitigation: native JSONL read/write (like beadster macOS app)

initial sync:
- issue: first sync downloads everything
- mitigation: pagination, incremental pull with timestamps

conflict UI:
- issue: need good merge UI for content conflicts
- mitigation: last-write-wins for metadata, manual merge for content

## comparison to alternatives

vs CouchDB/PouchDB:
- simpler, more git-friendly, less automatic but more control

vs Firebase/Supabase:
- local-first vs cloud-first, works offline, git-native, more private

vs operational transform/CRDTs:
- simpler (last-write-wins), better for low-conflict use cases

vs plain SQLite:
- more portable (text export built-in), git-friendly, multi-device sync included

vs plain JSONL:
- adds fast queries/search without losing text portability

## architecture verdict

exceptionally well-designed for personal productivity and data management tools. hits rare sweet spot:

- simple enough to understand completely (no magic)
- powerful enough for real applications (search, sync, multi-client)
- flexible enough to extend (cloud sync, WebSockets, encryption)
- robust enough for production (auto-rebuild, conflict resolution)

scale sweet spot: 100-100,000 records per source

key insight: JSONL as canonical + SQLite as cache solves fundamental tension between human-readable/portable (JSONL) and fast-queryable (SQLite) without forcing choice

## implementation considerations for new apps

data model:
- design JSON schema (keep flat when possible)
- add version field to all records
- use ULIDs for IDs (sortable, unique)
- include created_at and updated_at timestamps

file structure:
```
.appname/
├── data.jsonl           main data
├── data.db              SQLite cache
├── config.toml          app configuration
└── .gitignore           ignore *.db files
```

CLI commands needed:
- init: create .appname/ directory
- create: add new record
- list: show records (queries SQLite)
- show: display single record
- update: modify record
- delete: remove record
- export: rebuild JSONL from SQLite
- import: rebuild SQLite from JSONL
- sync: sync with cloud

SQLite schema:
- mirror JSONL structure
- add indexes for common queries
- add FTS tables if full-text search needed
- keep denormalized (optimize for reads)

sync strategy:
- use beadster pattern (local JSONL + cloud D1)
- track sync metadata in separate table
- implement incremental push/pull
- handle conflicts with timestamps
- use device tracking for collision prevention

git integration:
- .gitignore: ignore *.db files
- commit JSONL files only
- use hooks for validation
- document merge conflict resolution

cloud layer (optional):
- cloudflare workers + D1 (like beadster)
- REST API for CRUD operations
- WebSocket for real-time notifications
- device_issue_tracking table for collisions
- source_sequences table for ID generation

mobile considerations:
- sandboxed apps write JSONL directly
- read SQLite for fast queries
- implement JSONL parser natively
- handle merge on conflict
- cache cloud data locally

## example: local-first notes system design

structure:
```
.notes/
├── notes.jsonl
├── notes.db
├── attachments/
└── config.toml
```

JSONL format:
```json
{"id":"note-1","title":"Meeting notes","body":"# Meeting\n\n- Point 1","tags":["work","meeting"],"created_at":1234567890,"updated_at":1234567890}
```

SQLite schema:
```sql
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT,
  tags TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE VIRTUAL TABLE notes_fts USING fts5(title, body, content=notes);

CREATE TABLE tags (
  note_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (note_id, tag)
);
```

CLI commands:
```bash
notes init
notes create "Meeting notes"
notes list --tag work
notes show note-1
notes update note-1 --add-tag urgent
notes search "project alpha"
notes sync
```

sync metadata:
```sql
CREATE TABLE notes_sync (
  note_id TEXT PRIMARY KEY,
  cloud_id TEXT NOT NULL,
  synced_at INTEGER NOT NULL,
  cloud_updated_at INTEGER,
  local_updated_at INTEGER,
  sync_status TEXT DEFAULT 'synced'
);
```

this gives you:
- portable notes (plain JSONL)
- fast full-text search (SQLite FTS)
- version history (git)
- multi-device sync (cloud)
- CLI automation (scripting)
- GUI richness (native apps)
- privacy (local-first)
