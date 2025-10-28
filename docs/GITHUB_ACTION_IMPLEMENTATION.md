# GitHub Action implementation

complete implementation guide for beadster-sync-action

## repository: systemoperator/beadster-sync-action

GitHub Action for syncing beads issues to beadster cloud during CI/CD workflows.

## repository structure

```
beadster-sync-action/
├── action.yml              # action metadata
├── src/
│   ├── index.ts           # main entry point
│   ├── sync.ts            # sync logic
│   └── api.ts             # beadster API client
├── dist/
│   └── index.js           # compiled (committed to git)
├── package.json
├── tsconfig.json
├── .github/
│   └── workflows/
│       ├── test.yml       # test action on push
│       └── release.yml    # publish on tag
├── README.md
└── LICENSE (MIT)
```

## action.yml

```yaml
name: 'beadster sync'
description: 'sync beads issues to beadster cloud'
author: 'system operator'

branding:
  icon: 'check-circle'
  color: 'blue'

inputs:
  beadster_token:
    description: 'beadster API token (required)'
    required: true
  beadster_url:
    description: 'beadster API URL'
    required: false
    default: 'https://beadster.ai'
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

## src/index.ts

```typescript
import * as core from '@actions/core';
import * as github from '@actions/github';
import { sync } from './sync';

async function run() {
  try {
    // get inputs
    const beadsterToken = core.getInput('beadster_token', { required: true });
    const beadsterUrl = core.getInput('beadster_url') || 'https://beadster.ai';
    const beadsPath = core.getInput('beads_path') || '.beads';
    const sourceName = core.getInput('source_name') || github.context.repo.repo;
    const failOnError = core.getInput('fail_on_error') === 'true';

    core.info(`syncing beads from ${beadsPath}...`);
    core.info(`target: ${sourceName}`);
    core.info(`beadster: ${beadsterUrl}`);

    // run sync
    const result = await sync({
      beadsterToken,
      beadsterUrl,
      beadsPath,
      sourceName,
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

## src/sync.ts

```typescript
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import * as core from '@actions/core';
import { BeadsterAPI } from './api';

export interface SyncOptions {
  beadsterToken: string;
  beadsterUrl: string;
  beadsPath: string;
  sourceName: string;
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
  const { beadsterToken, beadsterUrl, beadsPath, sourceName, repoUrl, branch } = options;

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
  const api = new BeadsterAPI(beadsterUrl, beadsterToken);

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

## src/api.ts

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
        'User-Agent': 'beadster-sync-action/1.0',
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
    const { sources } = await this.fetch('/api/sources');

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

## package.json

```json
{
  "name": "beadster-sync-action",
  "version": "1.0.0",
  "description": "GitHub Action to sync beads issues to beadster cloud",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc && ncc build src/index.ts -o dist",
    "test": "jest",
    "lint": "eslint src/**/*.ts"
  },
  "keywords": [
    "github-action",
    "beads",
    "beadster",
    "issue-tracking"
  ],
  "author": "system operator",
  "license": "MIT",
  "dependencies": {
    "@actions/core": "^1.10.1",
    "@actions/github": "^6.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "@vercel/ncc": "^0.38.1",
    "typescript": "^5.3.3"
  }
}
```

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

## .github/workflows/test.yml

```yaml
name: test action

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: setup node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: install dependencies
        run: npm install

      - name: build
        run: npm run build

      - name: test action
        uses: ./
        with:
          beadster_token: ${{ secrets.BEADSTER_TEST_TOKEN }}
          fail_on_error: false
```

## .github/workflows/release.yml

```yaml
name: release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: setup node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: install dependencies
        run: npm install

      - name: build
        run: npm run build

      - name: create release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            dist/index.js
            action.yml
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## README.md

```markdown
# beadster sync action

GitHub Action to sync beads issues to beadster cloud during CI/CD workflows.

## usage

### quick start

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

### inputs

| input | description | required | default |
|-------|-------------|----------|---------|
| `beadster_token` | beadster API token | yes | - |
| `beadster_url` | beadster API URL | no | https://beadster.ai |
| `beads_path` | path to .beads directory | no | .beads |
| `source_name` | source name | no | repo name |
| `fail_on_error` | fail workflow on error | no | false |

### outputs

| output | description |
|--------|-------------|
| `synced` | number of issues synced |
| `source_id` | beadster source ID |
| `created` | number of issues created |
| `updated` | number of issues updated |

### examples

#### sync on push

```yaml
name: sync on push

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

#### sync on schedule

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

#### sync before deployment

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
      - name: deploy
        run: ./deploy.sh
```

## setup

### 1. get beadster token

visit beadster.ai/settings/tokens and create a new token:
1. click "create new token"
2. name it: "github-actions-myrepo"
3. select scope: "sync"
4. copy the token (starts with `bst_`)

### 2. add token to GitHub secrets

1. go to your repo settings
2. navigate to secrets and variables → actions
3. click "new repository secret"
4. name: `BEADSTER_TOKEN`
5. value: paste your token
6. click "add secret"

### 3. create workflow

create `.github/workflows/sync-beadster.yml`:

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

## how it works

1. checks if `.beads/issues.jsonl` exists
2. parses all issues from JSONL
3. gets or creates source in beadster
4. syncs each issue (create or update)
5. outputs sync statistics

## security

- tokens use scoped permissions (sync, read, admin)
- tokens can expire automatically
- usage is tracked and audited
- tokens can be revoked anytime

## license

MIT
```

## deployment steps

1. **create repository**
   ```bash
   mkdir beadster-sync-action
   cd beadster-sync-action
   git init
   ```

2. **setup project**
   ```bash
   npm init -y
   npm install @actions/core @actions/github
   npm install -D @types/node @vercel/ncc typescript
   ```

3. **add files**
   - copy all files above
   - create src/ directory with index.ts, sync.ts, api.ts

4. **build**
   ```bash
   npm run build
   ```

5. **commit dist/**
   ```bash
   git add dist/index.js
   git commit -m "build action"
   ```

6. **push to GitHub**
   ```bash
   git remote add origin git@github.com:systemoperator/beadster-sync-action.git
   git push -u origin main
   ```

7. **create release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

8. **publish to marketplace**
   - go to repository on GitHub
   - click "releases" → "create a new release"
   - select tag v1.0.0
   - check "publish this action to GitHub Marketplace"
   - fill in details
   - publish release

## testing locally

```bash
# set environment variables
export INPUT_BEADSTER_TOKEN=bst_your_token_here
export INPUT_BEADS_PATH=.beads
export GITHUB_REPOSITORY=owner/repo
export GITHUB_REF=refs/heads/main

# run action
node dist/index.js
```

## troubleshooting

**no .beads directory found**
- action skips sync if no .beads directory
- not an error condition

**unauthorized**
- check token is valid: beadster.ai/settings/tokens
- verify token has "sync" scope
- check token hasn't expired

**source not found**
- source is created automatically if not exists
- check user owns the source

**rate limiting**
- GitHub Actions has no rate limits for beadster API
- each run syncs all issues efficiently
