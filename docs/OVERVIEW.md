# beadster overview

github for bd (beads issue tracker)

## concept

bd is to git what beadster is to github

- bd: local git-backed issue tracker for AI agents
- beadster: cloud platform to view, manage, and sync all your beads issues across devices

## the problem

you have:
- 30+ coding projects (each with .beads/)
- personal tasks (no specific repo)
- company work
- ngo projects
- random sessions in claude code/desktop

how do you see everything in one place? access from mobile? edit in nice ui?

## the solution

beadster aggregates all your beads issues and provides beautiful UIs

```
git                    →    github
local repos            →    cloud view of all repos
git push/pull          →    sync
cli only               →    beautiful web ui
per-repo               →    cross-repo search

bd (beads)             →    beadster
.beads/ directories    →    cloud view of all issues
bd sync                →    auto-sync daemon
cli only               →    web + ios + macos apps
per-project            →    see all issues
```

## architecture

### local layer

```
~/projects/
├── project-a/.beads/
├── project-b/.beads/
└── company-site/.beads/

~/Documents/
└── random-ideas/.beads/
```

sync daemon watches all .beads/ directories and syncs to cloud

### cloud layer

cloudflare workers + d1

```sql
CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT,
  type TEXT,
  path TEXT,
  machine_id TEXT,
  last_sync INTEGER
);

CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  beads_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  status TEXT,
  priority TEXT,
  labels TEXT,
  blocks TEXT,
  blocked_by TEXT,
  parent_id TEXT,
  session_id TEXT,
  client TEXT,
  device_id TEXT,
  created_at INTEGER,
  updated_at INTEGER
);
```

### sync flow

```
1. agent creates issue with bd
2. beads writes to .beads/issues/issue-123.jsonl
3. sync daemon detects new file
4. sync daemon pushes to cloudflare d1
5. cloud broadcasts via websocket
6. web app shows new issue immediately
7. mobile app receives push notification
```

## key features

### auto-discovery

no manual setup - sync daemon finds all .beads/ directories automatically

```bash
brew install beadster
beadster discover
# scans ~/projects, ~/work for .beads/
# registers all found

beadster sync start
# watches all registered sources
```

### cross-device sync

```
mac app (with local .beads/):
  reads ~/projects/main-app/.beads/
  syncs to cloud
  writes back changes from cloud

ios app:
  reads from cloud
  caches locally
  writes to cloud

result: both stay in sync via cloud
```

### session tracking

every issue captures which claude session created it:

```json
{
  "title": "fix login bug",
  "labels": [
    "session:session_abc123",
    "client:claude-code",
    "device:device_xyz",
    "project:main-app"
  ]
}
```

query: "show todos from this conversation"
query: "what did i do in claude code today?"

### device tracking

track which device created/updated each issue:

```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  hardware_uuid TEXT UNIQUE,
  device_name TEXT,
  device_type TEXT,
  platform TEXT
);
```

issues track created_by_device_id and updated_by_device_id

## multiple sources

beadster handles different types of sources:

```
sources:
  main-app (coding project, local .beads/)
  side-project (coding project, local .beads/)
  personal (inbox, local .beads/)
  client-work (cloud-only, no local .beads/)
```

you can:
- view all issues across all sources
- filter by source
- see ready work across all projects
- create cloud-only sources

## mcp integration

beadster mcp server provides tools:

```typescript
tools:
  - todo_create: create issue (auto-detects source)
  - todo_list: list issues (filter by source/session/client)
  - todo_ready: show ready work (no blockers)
  - todo_update: update issue
  - todo_show: show details with dependencies
```

detects context automatically:
- in git repo? uses that source
- in subdirectory? finds parent .beads/
- random location? uses personal inbox

## web ui

```
beadster.com

all issues (342)
├─ ready work (47)
├─ by source
│  ├─ main-app (23 issues)
│  ├─ side-project (5 issues)
│  └─ personal (12 issues)
├─ by session
│  ├─ claude code - today 2:30 pm (5 issues)
│  └─ claude desktop - yesterday (3 issues)
└─ by device
   ├─ macbook pro (234 issues)
   └─ iphone (45 issues)
```

## mobile apps

native ios/mac apps using same api:
- view all issues
- create new issues
- mark complete
- filter by source/session/device
- works offline with cache

## identity

user identity: apple id (sign in with apple)
device identity: hardware uuid (per machine)
session identity: conversation id (per chat)
client identity: which app (claude-code, web, ios-app)

all tracked together for full context

## offline support

local .beads/ works offline:
- agent uses bd cli (works without internet)
- beads writes to local sqlite
- sync daemon queues changes
- when online, syncs to cloud

cloud-only mode:
- no local .beads/ needed
- all operations via api
- requires internet

## why beadster

bd alone:
- per-repo only
- requires git sync between machines
- cli-focused
- no cross-platform access
- no visual ui

bd + beadster:
- aggregate all repos
- real-time cloud sync
- web + mobile apps
- cross-device access
- beautiful ui
- keeps all bd benefits (git-backed, offline, dependencies)

beadster is the shared server that makes bd work for teams and across devices
