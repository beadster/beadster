# beads features analysis

analysis of new beads features and implementation plan for beadster (macOS app + web)

## new beads features (from changelog)

### 1. external_ref field
- purpose: hybrid workflows with Jira, GitHub, Linear
- smart matching prevents duplicate creation
- database index for fast lookups
- **status in bd CLI**: ✅ implemented (v1.x)

### 2. merge and duplicates
- `bd merge` - consolidate duplicate issues with automatic dependency migration
- `bd duplicates` - detect duplicates with `--auto-merge` and `--dry-run` modes
- **status in bd CLI**: ✅ implemented

### 3. config management
- `bd config` - manage environment variables and config files (TOML/YAML/JSON)
- **status in bd CLI**: ✅ implemented

### 4. git hooks
- pre-commit, post-merge hooks auto-installed during `bd init`
- **status in bd CLI**: ✅ implemented

### 5. bd onboard
- generates agent-first documentation integration instructions
- **status in bd CLI**: ✅ implemented

### 6. label filtering enhancements
- `--label` - filters requiring ALL labels (AND semantics)
- `--label-any` - filters with OR semantics (AT LEAST ONE)
- **status in bd CLI**: ✅ implemented

### 7. multi-id operations
- supports multiple IDs across update, show, label, close, reopen commands
- **status in bd CLI**: ✅ implemented

### 8. daemon improvements
- file-level locking prevents multiple daemons per repository
- daemon log rotation with configurable size/backup/age
- removed global daemon socket fallback
- **status in bd CLI**: ✅ implemented

### 9. delete operations
- `bd delete` with batch operations, cascade/force modes, atomic transactions
- **status in bd CLI**: ✅ implemented

### 10. bd ready enhancements
- `bd ready --sort` with three policies: hybrid (default), priority, oldest
- **status in bd CLI**: ✅ implemented

## beadster current implementation status

### macOS app

architecture:
- reads from `.beads/beadster.db` (SQLite cache)
- writes to `.beads/issues.jsonl` (source of truth)
- sandboxed - CANNOT execute bd CLI

current features:
- ✅ read/write issues (CRUD)
- ✅ status management (open/in_progress/blocked/closed)
- ✅ priority (P0-P4)
- ✅ labels
- ✅ git context capture
- ✅ cloud sync
- ❌ external_ref field (NOT supported)
- ❌ dependencies (NOT supported)
- ❌ merge/duplicates (NOT supported)
- ❌ config management (NOT supported)
- ❌ label filtering (basic only)

### web app

architecture:
- cloudflare workers + D1 database
- astro SSR + better-auth
- GitHub OAuth implemented

current features:
- ✅ issue listing/viewing
- ✅ create/update/close issues via API
- ✅ session tracking
- ✅ git repository grouping
- ✅ stats dashboard
- ❌ external_ref field (NOT in schema)
- ❌ dependencies (NOT in schema)
- ❌ GitHub import (NOT implemented)
- ❌ GitHub Actions sync (documented but NOT implemented)
- ❌ label filtering with AND/OR (NOT implemented)

## implementation priorities

### priority 1: external_ref support (foundation)

enables hybrid workflows and GitHub import

**macOS app changes:**
- add `externalRef` field to `Issue` model (Models.swift:116)
- update JSONL encoder/decoder
- update issue creation UI to optionally capture external_ref
- display external_ref in issue detail view

**web app changes:**
- add `external_ref TEXT` to issues table schema
- add index: `CREATE INDEX idx_issues_external_ref ON issues(external_ref)`
- update API endpoints to accept/return external_ref
- update frontend to display external_ref

**shared changes:**
- update beads_schema.sql with external_ref (already present in bd schema)
- ensure all issue models support external_ref

**effort**: medium (1-2 days)
**impact**: high (foundation for GitHub import)

### priority 2: GitHub import for web

enable web app to import any GitHub repo with beads

**features needed:**
- import page: paste GitHub repo URL
- fetch `.beads/issues.jsonl` from GitHub API
- parse JSONL and import to D1 database
- create source record for imported repo
- handle external_ref matching (no duplicates)
- display import progress/status

**implementation:**
- new page: `/import` (or `/repositories/import`)
- API endpoint: `POST /api/import/github`
- use GitHub API to fetch raw file content
- parse JSONL line by line
- create/update issues with external_ref matching
- create source with type='github-import'

**GitHub API usage:**
```typescript
// fetch issues.jsonl from public repo
const url = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/.beads/issues.jsonl`;
const response = await fetch(url);
const jsonl = await response.text();

// for private repos (requires OAuth token)
const url = `https://api.github.com/repos/${owner}/${repo}/contents/.beads/issues.jsonl`;
const response = await fetch(url, {
  headers: {
    'Authorization': `Bearer ${githubToken}`,
    'Accept': 'application/vnd.github.v3.raw'
  }
});
```

**external_ref format for GitHub:**
- `github:owner/repo:issue-id` (e.g., `github:steveyegge/beads:bd-123`)
- enables matching across imports

**effort**: high (3-5 days)
**impact**: very high (core web feature)

### priority 3: GitHub Actions integration

automate sync from GitHub workflows

**implementation:**
- create GitHub Action repo: `systemoperator/beadster-sync-action`
- implement action.yml + TypeScript entry point
- add API endpoints for token-based sync
- implement token management in web app
- add audit logging

**API endpoints needed:**
- `POST /api/tokens` - create sync token
- `GET /api/tokens` - list user tokens
- `DELETE /api/tokens/:id` - revoke token
- `GET /api/sources` - list sources (with token auth)
- `POST /api/sources/:id/sync` - batch sync issues

**token scopes:**
- `sync` - read and write issues
- `read` - read-only access
- `admin` - full access to source

**effort**: high (5-7 days)
**impact**: high (enables CI/CD workflows)

### priority 4: label filtering (AND/OR semantics)

match beads CLI behavior

**macOS app:**
- add label filter UI with AND/OR toggle
- implement filtering logic in IssueStore
- persist filter preference

**web app:**
- add label filter UI on index page
- update API to support `?label=foo,bar&label_match=all` or `label_match=any`
- implement filtering in database queries

**effort**: low (1 day)
**impact**: medium (power user feature)

### priority 5: dependencies support

enable dependency tracking and visualization

**macOS app:**
- add dependencies table support
- UI for adding/removing dependencies
- visualize dependencies (blocks, related, parent-child)
- support "discovered-from" type

**web app:**
- add dependencies table to schema
- API endpoints for managing dependencies
- dependency graph visualization
- filter by blocked/ready status

**effort**: very high (10-15 days)
**impact**: very high (complex but powerful feature)

### priority 6: merge/duplicates

duplicate detection and merging

**macOS app:**
- not feasible (requires bd CLI)
- show duplicate warnings only

**web app:**
- implement duplicate detection algorithm
- UI for reviewing duplicates
- merge operation with dependency migration
- preview before merge

**effort**: very high (7-10 days)
**impact**: medium (useful but not critical)

## feature matrix: macOS vs web

| feature | macOS app | web | notes |
|---------|-----------|-----|-------|
| basic CRUD | ✅ | ✅ | both support |
| external_ref | 🔨 priority 1 | 🔨 priority 1 | foundation for import |
| GitHub import | ❌ not needed | 🔨 priority 2 | web-only feature |
| GitHub Actions | ❌ not needed | 🔨 priority 3 | web API feature |
| label AND/OR | 🔨 priority 4 | 🔨 priority 4 | match bd CLI |
| dependencies | 🔨 priority 5 | 🔨 priority 5 | complex feature |
| merge/duplicates | ❌ needs bd CLI | 🔨 priority 6 | web can implement |
| config mgmt | ❌ needs bd CLI | ❌ not planned | CLI-only |
| git hooks | ❌ needs bd CLI | ❌ not planned | CLI-only |
| bd onboard | ❌ needs bd CLI | ❌ not planned | CLI-only |
| daemon features | ❌ needs bd CLI | ❌ not planned | CLI-only |

legend:
- ✅ implemented
- 🔨 planned (priority number)
- ❌ not planned/not feasible

## GitHub import detailed design

### import flow

1. user enters GitHub repo URL
2. web app fetches `.beads/issues.jsonl`
3. parse JSONL line by line
4. for each issue:
   - check if external_ref exists
   - if exists: update existing issue
   - if not: create new issue with external_ref
5. create/update source record
6. show import summary

### external_ref format

standard format: `github:owner/repo:issue-id`

examples:
- `github:steveyegge/beads:bd-1`
- `github:systemoperator/beadster:beadster-123`

### matching logic

```typescript
async function importIssue(db: D1Database, userId: string, sourceId: string, issue: any, repoUrl: string) {
  const externalRef = `github:${extractOwnerRepo(repoUrl)}:${issue.id}`;

  // check for existing issue by external_ref
  const existing = await db.prepare(`
    SELECT id FROM issues
    WHERE user_id = ? AND external_ref = ?
  `).bind(userId, externalRef).first();

  if (existing) {
    // update existing
    await updateIssue(db, existing.id, issue);
  } else {
    // create new with external_ref
    await createIssue(db, {
      ...issue,
      userId,
      sourceId,
      externalRef
    });
  }
}
```

### UI mockup

```
┌─────────────────────────────────────────┐
│ import from GitHub                      │
├─────────────────────────────────────────┤
│                                         │
│ GitHub repository URL:                  │
│ ┌─────────────────────────────────────┐ │
│ │ https://github.com/user/repo        │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ branch (optional):                      │
│ ┌─────────────────────────────────────┐ │
│ │ main                                │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ [  ] use my GitHub token (for private)  │
│                                         │
│              [ import ]                 │
│                                         │
└─────────────────────────────────────────┘

after import:

✅ imported 47 issues from steveyegge/beads
   - created: 45
   - updated: 2
   - skipped: 0

[view imported issues]
```

### error handling

- repo not found → show friendly error
- no .beads directory → show "repo doesn't use beads"
- private repo without token → prompt for GitHub OAuth
- network errors → retry with exponential backoff
- malformed JSONL → show line number and error

## GitHub Actions detailed design

### action repository

new repo: `systemoperator/beadster-sync-action`

structure:
```
beadster-sync-action/
├── action.yml
├── src/
│   ├── index.ts
│   ├── sync.ts
│   └── api.ts
├── dist/
│   └── index.js (compiled)
├── package.json
└── README.md
```

### workflow example

```yaml
name: sync beadster

on:
  push:
    branches: [main]

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}
```

### API token architecture

tokens table:
```sql
CREATE TABLE api_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  token TEXT UNIQUE NOT NULL,  -- bst_xxxxxxxx
  scopes TEXT NOT NULL,  -- JSON array: ["sync", "read"]
  last_used INTEGER,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,  -- NULL = no expiration
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_tokens_token ON api_tokens(token);
CREATE INDEX idx_api_tokens_user ON api_tokens(user_id);
```

token format: `bst_` prefix + 32 random chars

### sync API endpoint

```typescript
// POST /api/sources/:source_id/sync
export async function POST({ request, locals }: APIContext) {
  // authenticate with token (not session)
  const authHeader = request.headers.get('authorization');
  const token = authHeader?.replace('Bearer ', '');

  if (!token) {
    return new Response('unauthorized', { status: 401 });
  }

  const tokenRecord = await db.prepare(
    'SELECT user_id, scopes FROM api_tokens WHERE token = ?'
  ).bind(token).first();

  if (!tokenRecord || !tokenRecord.scopes.includes('sync')) {
    return new Response('forbidden', { status: 403 });
  }

  // parse issues from request body
  const { issues } = await request.json();

  // sync each issue
  let created = 0, updated = 0;
  for (const issue of issues) {
    const existing = await db.prepare(
      'SELECT id FROM issues WHERE source_id = ? AND beads_id = ?'
    ).bind(sourceId, issue.id).first();

    if (existing) {
      await updateIssue(db, existing.id, issue);
      updated++;
    } else {
      await createIssue(db, { ...issue, sourceId, userId: tokenRecord.user_id });
      created++;
    }
  }

  return Response.json({ created, updated, synced: created + updated });
}
```

## next steps

1. implement external_ref support (priority 1)
   - update macOS app models
   - update web schema and API
   - add UI for viewing external_ref

2. implement GitHub import for web (priority 2)
   - create import page
   - implement GitHub API fetching
   - add matching logic
   - test with public/private repos

3. implement GitHub Actions (priority 3)
   - create action repository
   - implement token management
   - add sync API endpoints
   - publish to GitHub Marketplace

4. implement label filtering (priority 4)
   - update macOS app UI
   - update web app UI and API
   - test AND/OR semantics

5. plan dependencies support (priority 5)
   - design schema changes
   - design UI/UX
   - implement incrementally

## questions for user

1. should GitHub import support private repos? (requires OAuth scope changes)
2. should we auto-sync imported repos on schedule? (periodic re-import)
3. should external_ref be editable by users or auto-generated only?
4. what token expiration policy? (30 days, 90 days, never?)
5. should we support other git hosts (GitLab, Bitbucket)?
