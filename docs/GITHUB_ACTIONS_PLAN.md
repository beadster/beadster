# GitHub Actions implementation plan

detailed plan for implementing beadster-sync-action for GitHub Actions integration

## overview

create GitHub Action that syncs `.beads/issues.jsonl` to beadster cloud during CI/CD workflows

enables:
- automated sync on push
- scheduled sync (nightly, hourly)
- sync before deployment
- server-side sync without desktop app

## repository structure

new repository: `systemoperator/beadster-sync-action`

```
beadster-sync-action/
├── action.yml              # action metadata
├── src/
│   ├── index.ts           # main entry point
│   ├── sync.ts            # sync logic
│   ├── github.ts          # GitHub context helpers
│   └── api.ts             # beadster API client
├── dist/
│   └── index.js           # compiled (committed)
├── package.json
├── tsconfig.json
├── README.md
├── LICENSE
└── .github/
    └── workflows/
        ├── test.yml       # test action
        └── publish.yml    # publish to marketplace
```

## implementation phases

### phase 1: action scaffolding
- create repository
- setup TypeScript build
- create action.yml metadata
- implement basic structure

### phase 2: beadster API integration
- design API token system
- implement token endpoints
- add token management UI
- implement sync endpoint

### phase 3: action implementation
- implement JSONL parsing
- implement source matching
- implement issue sync
- add error handling

### phase 4: testing and publishing
- create test workflow
- test with real repos
- publish to marketplace
- write documentation

## detailed implementation

### 1. action.yml

```yaml
name: 'beadster sync'
description: 'sync bd issues to beadster cloud'
author: 'system operator'

branding:
  icon: 'check-circle'
  color: 'blue'

inputs:
  beadster_token:
    description: 'beadster api token (required)'
    required: true
  beads_path:
    description: 'path to .beads directory'
    required: false
    default: '.beads'
  source_name:
    description: 'source name (defaults to repo name)'
    required: false
  fail_on_error:
    description: 'fail workflow on sync error'
    required: false
    default: 'false'
  api_url:
    description: 'beadster API URL'
    required: false
    default: 'https://beadster.com'

outputs:
  synced:
    description: 'number of issues synced'
  source_id:
    description: 'beadster source ID'
  created:
    description: 'number of issues created'
  updated:
    description: 'number of issues updated'

runs:
  using: 'node20'
  main: 'dist/index.js'
```

### 2. src/index.ts

```typescript
import * as core from '@actions/core';
import * as github from '@actions/github';
import { sync } from './sync';

async function run() {
  try {
    // get inputs
    const beadsterToken = core.getInput('beadster_token', { required: true });
    const beadsPath = core.getInput('beads_path') || '.beads';
    const sourceName = core.getInput('source_name') || github.context.repo.repo;
    const failOnError = core.getInput('fail_on_error') === 'true';
    const apiUrl = core.getInput('api_url') || 'https://beadster.com';

    core.info(`syncing beads from ${beadsPath}...`);
    core.info(`target source: ${sourceName}`);

    // run sync
    const result = await sync({
      beadsterToken,
      beadsPath,
      sourceName,
      apiUrl,
      repoUrl: `https://github.com/${github.context.repo.owner}/${github.context.repo.repo}`,
      branch: github.context.ref.replace('refs/heads/', '')
    });

    // set outputs
    core.setOutput('synced', result.created + result.updated);
    core.setOutput('source_id', result.sourceId);
    core.setOutput('created', result.created);
    core.setOutput('updated', result.updated);

    core.info(`✅ sync completed: ${result.created} created, ${result.updated} updated`);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (core.getInput('fail_on_error') === 'true') {
      core.setFailed(message);
    } else {
      core.warning(`sync failed: ${message}`);
    }
  }
}

run();
```

### 3. src/sync.ts

```typescript
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import * as core from '@actions/core';
import { BeadsterAPI } from './api';

export interface SyncOptions {
  beadsterToken: string;
  beadsPath: string;
  sourceName: string;
  apiUrl: string;
  repoUrl: string;
  branch: string;
}

export interface SyncResult {
  sourceId: string;
  created: number;
  updated: number;
  skipped: number;
}

export async function sync(options: SyncOptions): Promise<SyncResult> {
  const { beadsterToken, beadsPath, sourceName, apiUrl, repoUrl, branch } = options;

  // check if .beads exists
  if (!existsSync(beadsPath)) {
    core.info(`no .beads directory found at ${beadsPath} - skipping sync`);
    return { sourceId: '', created: 0, updated: 0, skipped: 0 };
  }

  // read issues.jsonl
  const issuesFile = join(beadsPath, 'issues.jsonl');
  if (!existsSync(issuesFile)) {
    core.info('no issues.jsonl found - skipping sync');
    return { sourceId: '', created: 0, updated: 0, skipped: 0 };
  }

  const jsonl = readFileSync(issuesFile, 'utf8');
  const lines = jsonl.split('\n').filter(line => line.trim());
  const issues = lines.map(line => JSON.parse(line));

  core.info(`found ${issues.length} issues in ${issuesFile}`);

  // create API client
  const api = new BeadsterAPI(apiUrl, beadsterToken);

  // get or create source
  const source = await api.getOrCreateSource(sourceName, repoUrl, branch);
  core.info(`using source: ${source.id} (${source.name})`);

  // sync issues
  const result = await api.syncIssues(source.id, issues);
  core.info(`synced ${result.created} created, ${result.updated} updated, ${result.skipped} skipped`);

  return {
    sourceId: source.id,
    ...result
  };
}
```

### 4. src/api.ts

```typescript
export interface Source {
  id: string;
  name: string;
  type: string;
  git_repo_url?: string;
  git_current_branch?: string;
}

export interface SyncResponse {
  created: number;
  updated: number;
  skipped: number;
}

export class BeadsterAPI {
  constructor(
    private baseUrl: string,
    private token: string
  ) {}

  private async fetch(path: string, options: RequestInit = {}) {
    const url = `${this.baseUrl}${path}`;
    const response = await fetch(url, {
      ...options,
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json',
        'User-Agent': 'beadster-sync-action',
        ...options.headers
      }
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`API error (${response.status}): ${text}`);
    }

    return response.json();
  }

  async getOrCreateSource(name: string, repoUrl: string, branch: string): Promise<Source> {
    // list sources
    const sources = await this.fetch('/api/sources');

    // find existing by git_repo_url
    const existing = sources.find((s: Source) => s.git_repo_url === repoUrl);

    if (existing) {
      // update branch if changed
      if (existing.git_current_branch !== branch) {
        return await this.fetch(`/api/sources/${existing.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ git_current_branch: branch })
        });
      }
      return existing;
    }

    // create new source
    return await this.fetch('/api/sources', {
      method: 'POST',
      body: JSON.stringify({
        name,
        type: 'local-git',
        git_repo_url: repoUrl,
        git_current_branch: branch
      })
    });
  }

  async syncIssues(sourceId: string, issues: any[]): Promise<SyncResponse> {
    return await this.fetch(`/api/sources/${sourceId}/sync`, {
      method: 'POST',
      body: JSON.stringify({ issues })
    });
  }
}
```

### 5. API token system

#### database schema

```sql
CREATE TABLE api_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  token TEXT UNIQUE NOT NULL,
  scopes TEXT NOT NULL,  -- JSON array
  last_used INTEGER,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,  -- NULL = never expires
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_tokens_token ON api_tokens(token);
CREATE INDEX idx_api_tokens_user ON api_tokens(user_id);

CREATE TABLE api_token_usage (
  id TEXT PRIMARY KEY,
  token_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  status INTEGER NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (token_id) REFERENCES api_tokens(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_token_usage_token ON api_token_usage(token_id);
CREATE INDEX idx_api_token_usage_created ON api_token_usage(created_at);
```

#### token format

`bst_` + 32 random characters (base62)

example: `bst_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`

#### scopes

- `sync` - create and update issues
- `read` - read-only access to issues and sources
- `admin` - full access (delete, manage sources)

#### API endpoints

**POST /api/tokens** - create token
```json
{
  "name": "github-actions-myrepo",
  "scopes": ["sync"]
}
```

**GET /api/tokens** - list tokens
```json
{
  "tokens": [
    {
      "id": "tok_xxx",
      "name": "github-actions-myrepo",
      "scopes": ["sync"],
      "last_used": 1234567890,
      "created_at": 1234567890
    }
  ]
}
```

**DELETE /api/tokens/:id** - revoke token

**GET /api/tokens/:id/usage** - get usage logs

### 6. sync API endpoint

**POST /api/sources/:source_id/sync**

batch sync issues from JSONL

request:
```json
{
  "issues": [
    {
      "id": "bd-1",
      "title": "fix bug",
      "status": "open",
      "priority": 2,
      "created_at": "2025-01-01T00:00:00Z",
      "updated_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

response:
```json
{
  "created": 1,
  "updated": 0,
  "skipped": 0
}
```

implementation:
```typescript
export async function POST({ request, params, locals }: APIContext) {
  const { source_id } = params;

  // authenticate with token
  const authHeader = request.headers.get('authorization');
  const token = authHeader?.replace('Bearer ', '');

  if (!token) {
    return new Response('unauthorized', { status: 401 });
  }

  const db = locals.runtime?.env?.DB;
  const tokenRecord = await db.prepare(
    'SELECT user_id, scopes FROM api_tokens WHERE token = ?'
  ).bind(token).first();

  if (!tokenRecord) {
    return new Response('invalid token', { status: 401 });
  }

  const scopes = JSON.parse(tokenRecord.scopes);
  if (!scopes.includes('sync') && !scopes.includes('admin')) {
    return new Response('insufficient permissions', { status: 403 });
  }

  // verify source belongs to user
  const source = await db.prepare(
    'SELECT id FROM sources WHERE id = ? AND user_id = ?'
  ).bind(source_id, tokenRecord.user_id).first();

  if (!source) {
    return new Response('source not found', { status: 404 });
  }

  // parse issues
  const { issues } = await request.json();
  if (!Array.isArray(issues)) {
    return new Response('invalid request: issues must be array', { status: 400 });
  }

  // sync each issue
  let created = 0, updated = 0, skipped = 0;

  for (const issue of issues) {
    try {
      const result = await syncIssue(db, tokenRecord.user_id, source_id, issue);
      if (result === 'created') created++;
      else if (result === 'updated') updated++;
      else skipped++;
    } catch (err) {
      console.error('failed to sync issue:', issue.id, err);
      skipped++;
    }
  }

  // log usage
  await db.prepare(`
    INSERT INTO api_token_usage (id, token_id, endpoint, method, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `).bind(
    generateId(),
    tokenRecord.id,
    `/api/sources/${source_id}/sync`,
    'POST',
    200,
    Date.now()
  ).run();

  return Response.json({ created, updated, skipped });
}

async function syncIssue(
  db: D1Database,
  userId: string,
  sourceId: string,
  issue: any
): Promise<'created' | 'updated' | 'skipped'> {
  // check if issue exists
  const existing = await db.prepare(`
    SELECT id, updated_at FROM issues
    WHERE user_id = ? AND source_id = ? AND beads_id = ?
  `).bind(userId, sourceId, issue.id).first();

  if (existing) {
    // check if source is newer
    const sourceUpdatedAt = parseTimestamp(issue.updated_at);
    if (sourceUpdatedAt > existing.updated_at) {
      await updateIssue(db, existing.id, issue);
      return 'updated';
    } else {
      return 'skipped';
    }
  } else {
    // create new
    await createIssue(db, userId, sourceId, issue);
    return 'created';
  }
}
```

### 7. token management UI

create `/src/web/src/pages/settings/tokens.astro`:

```astro
---
import Layout from '../../layouts/Layout.astro';

if (!Astro.locals.user) {
  return Astro.redirect('/login');
}

const db = Astro.locals.runtime?.env?.DB;
let tokens = [];

if (db) {
  const result = await db.prepare(`
    SELECT id, name, scopes, last_used, created_at
    FROM api_tokens
    WHERE user_id = ?
    ORDER BY created_at DESC
  `).bind(Astro.locals.user.id).all();

  tokens = result.results || [];
}
---

<Layout title="API tokens">
  <h2>API tokens</h2>

  <div class="description">
    tokens allow external tools (like GitHub Actions) to sync issues to beadster
  </div>

  <div class="tokens-list">
    {tokens.length === 0 && (
      <div class="empty">no tokens created</div>
    )}

    {tokens.map(token => (
      <div class="token-card">
        <div class="token-header">
          <h3>{token.name}</h3>
          <button class="revoke-btn" data-token-id={token.id}>revoke</button>
        </div>
        <div class="token-info">
          <span class="scopes">{JSON.parse(token.scopes).join(', ')}</span>
          {token.last_used && (
            <span class="last-used">
              last used: {new Date(token.last_used).toLocaleDateString()}
            </span>
          )}
        </div>
      </div>
    ))}
  </div>

  <button class="create-btn" id="createToken">create new token</button>
</Layout>
```

## testing strategy

### unit tests
- test JSONL parsing
- test API client
- test error handling

### integration tests
- test with mock API
- test token authentication
- test sync logic

### end-to-end tests
- test in real GitHub Action workflow
- test with real beadster API
- test error scenarios

## deployment checklist

- [ ] create systemoperator/beadster-sync-action repo
- [ ] implement action code
- [ ] compile and commit dist/
- [ ] add comprehensive README
- [ ] add LICENSE (MIT)
- [ ] create example workflows
- [ ] test with real repos
- [ ] publish to GitHub Marketplace
- [ ] announce in docs

## documentation

### README.md for action

include:
- quick start example
- input parameters reference
- output values reference
- workflow examples
- troubleshooting guide
- security best practices

### beadster docs

add section on GitHub Actions integration:
- how to get token
- how to add to repo secrets
- example workflows
- troubleshooting
