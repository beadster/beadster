# github actions integration

sync bd issues to beadster from ci/cd workflows

## overview

github action that syncs .beads/ directory to beadster cloud during ci/cd runs

use cases:
- sync after every push
- sync before deployment
- sync on schedule (nightly)
- sync from servers without desktop app

## action configuration

### basic setup

`.github/workflows/sync-beadster.yml`:

```yaml
name: sync beadster

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 */6 * * *'  # every 6 hours

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}
```

### advanced configuration

```yaml
- uses: systemoperator/beadster-sync-action@v1
  with:
    # required: beadster auth token
    beadster_token: ${{ secrets.BEADSTER_TOKEN }}

    # optional: path to .beads directory (default: .beads)
    beads_path: .beads

    # optional: source name (default: repo name)
    source_name: ${{ github.repository }}

    # optional: enable context capture (default: false)
    context_capture: false

    # optional: anthropic api key for context capture
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}

    # optional: fail on sync error (default: false)
    fail_on_error: false
```

## getting beadster token

### web ui

1. go to beadster.com/settings/tokens
2. click "create new token"
3. give it a name: "github actions - myrepo"
4. copy token: `bst_xxxxxxxx`
5. add to github repo secrets as `BEADSTER_TOKEN`

### api

```bash
curl -X POST https://beadster.com/api/tokens \
  -H "Authorization: Bearer $USER_TOKEN" \
  -d '{"name": "github-actions-myrepo", "scopes": ["sync"]}'
```

## action implementation

### action.yml

```yaml
name: 'beadster sync'
description: 'sync bd issues to beadster cloud'
author: 'system operator'

branding:
  icon: 'check-circle'
  color: 'blue'

inputs:
  beadster_token:
    description: 'beadster api token'
    required: true
  beads_path:
    description: 'path to .beads directory'
    required: false
    default: '.beads'
  source_name:
    description: 'source name (defaults to repo name)'
    required: false
  context_capture:
    description: 'enable context capture'
    required: false
    default: 'false'
  anthropic_api_key:
    description: 'anthropic api key for context capture'
    required: false
  fail_on_error:
    description: 'fail workflow on sync error'
    required: false
    default: 'false'

runs:
  using: 'node20'
  main: 'dist/index.js'
```

### index.ts

```typescript
import * as core from '@actions/core';
import * as github from '@actions/github';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

async function run() {
  try {
    // get inputs
    const beadsterToken = core.getInput('beadster_token', { required: true });
    const beadsPath = core.getInput('beads_path') || '.beads';
    const sourceName = core.getInput('source_name') || github.context.repo.repo;
    const contextCapture = core.getInput('context_capture') === 'true';
    const anthropicApiKey = core.getInput('anthropic_api_key');
    const failOnError = core.getInput('fail_on_error') === 'true';

    // check if .beads exists
    if (!existsSync(beadsPath)) {
      core.info(`no .beads directory found at ${beadsPath} - skipping sync`);
      return;
    }

    // read issues
    const issuesFile = join(beadsPath, 'issues.jsonl');
    if (!existsSync(issuesFile)) {
      core.info('no issues.jsonl found - skipping sync');
      return;
    }

    const issues = readFileSync(issuesFile, 'utf8')
      .split('\n')
      .filter(line => line.trim())
      .map(line => JSON.parse(line));

    core.info(`found ${issues.length} issues`);

    // get or create source
    const source = await getOrCreateSource(beadsterToken, sourceName);
    core.info(`syncing to source: ${source.id}`);

    // sync issues
    const result = await syncIssues(beadsterToken, source.id, issues);
    core.info(`synced ${result.created} created, ${result.updated} updated`);

    // context capture
    if (contextCapture && anthropicApiKey) {
      core.info('running context capture...');
      const enriched = await captureContext(beadsterToken, anthropicApiKey, source.id, issues);
      core.info(`enriched ${enriched} issues`);
    }

    // set outputs
    core.setOutput('synced', result.created + result.updated);
    core.setOutput('source_id', source.id);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (core.getInput('fail_on_error') === 'true') {
      core.setFailed(message);
    } else {
      core.warning(`sync failed: ${message}`);
    }
  }
}

async function getOrCreateSource(token: string, name: string) {
  // check if source exists
  const response = await fetch('https://beadster.com/api/sources', {
    headers: { 'Authorization': `Bearer ${token}` }
  });

  const sources = await response.json();
  const existing = sources.find(s => s.name === name);

  if (existing) {
    return existing;
  }

  // create new source
  const createResponse = await fetch('https://beadster.com/api/sources', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      name,
      type: 'local-git',
      cloud_only: false
    })
  });

  return await createResponse.json();
}

async function syncIssues(token: string, sourceId: string, issues: any[]) {
  const response = await fetch(`https://beadster.com/api/sources/${sourceId}/sync`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ issues })
  });

  if (!response.ok) {
    throw new Error(`sync failed: ${response.statusText}`);
  }

  return await response.json();
}

async function captureContext(token: string, anthropicApiKey: string, sourceId: string, issues: any[]) {
  const response = await fetch(`https://beadster.com/api/sources/${sourceId}/capture-context`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      anthropic_api_key: anthropicApiKey,
      issue_ids: issues.map(i => i.id)
    })
  });

  const result = await response.json();
  return result.enriched_count;
}

run();
```

## workflow examples

### sync on push

```yaml
name: sync beadster

on:
  push:
    branches: [main, develop]

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}
```

### sync on schedule

```yaml
name: nightly sync

on:
  schedule:
    - cron: '0 2 * * *'  # 2am daily

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}
```

### sync with context capture

```yaml
name: sync with context

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
          context_capture: true
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### sync multiple projects

```yaml
name: sync all projects

on:
  workflow_dispatch:

jobs:
  sync-api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: myorg/api
      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}
          source_name: api

  sync-web:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: myorg/web
      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}
          source_name: web
```

### sync before deploy

```yaml
name: deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # sync issues first
      - uses: systemoperator/beadster-sync-action@v1
        with:
          beadster_token: ${{ secrets.BEADSTER_TOKEN }}

      # then deploy
      - name: deploy to production
        run: ./deploy.sh
```

## api endpoints

### create token

```
POST /api/tokens
Authorization: Bearer <user-token>

{
  "name": "github-actions-myrepo",
  "scopes": ["sync"]
}

Response:
{
  "token": "bst_xxxxxxxxxx",
  "name": "github-actions-myrepo",
  "scopes": ["sync"],
  "created_at": 1234567890
}
```

### list sources

```
GET /api/sources
Authorization: Bearer <beadster-token>

Response:
[
  {
    "id": "src_xxx",
    "name": "myrepo",
    "type": "local-git",
    "last_sync": 1234567890
  }
]
```

### sync issues

```
POST /api/sources/:source_id/sync
Authorization: Bearer <beadster-token>

{
  "issues": [
    { "id": "bd-1", "title": "...", ... },
    { "id": "bd-2", "title": "...", ... }
  ]
}

Response:
{
  "created": 1,
  "updated": 1,
  "skipped": 0
}
```

## security

### token scopes

beadster tokens support granular scopes:
- `sync` - read and write issues
- `read` - read-only access
- `admin` - full access to source

### token rotation

rotate tokens regularly:

```bash
# create new token
curl -X POST https://beadster.com/api/tokens \
  -H "Authorization: Bearer $USER_TOKEN" \
  -d '{"name": "github-actions-myrepo-2", "scopes": ["sync"]}'

# update github secret with new token

# revoke old token
curl -X DELETE https://beadster.com/api/tokens/bst_old_token \
  -H "Authorization: Bearer $USER_TOKEN"
```

### audit log

view all token usage:

```
GET /api/tokens/:token_id/audit
Authorization: Bearer <user-token>

Response:
[
  {
    "timestamp": 1234567890,
    "action": "sync",
    "source_id": "src_xxx",
    "ip": "140.82.115.1",
    "user_agent": "github-actions"
  }
]
```

## benefits

- **automated sync**: no manual sync needed
- **consistent**: runs on schedule or every push
- **ci/cd integration**: sync before deployment
- **server support**: works without desktop app
- **context capture**: optional ai enrichment in ci/cd
- **multi-project**: sync multiple repos from one workflow
- **audit trail**: track all syncs in beadster

## limitations

- no bidirectional sync (push only from ci/cd)
- requires github secrets for tokens
- context capture needs anthropic api key
- works with github actions only (not other ci/cd yet)

## future enhancements

- gitlab ci support
- circleci support
- jenkins plugin
- bidirectional sync option
- auto-close issues from commits
- pr integration
