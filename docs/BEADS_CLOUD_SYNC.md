# Beads + Cloud Sync Architecture

## Vision

Build dual-purpose todo system (agents + humans) on top of Beads with cloud sync.

**Key insight:** Beads is the source of truth locally, Cloud is the aggregation + access layer.

## Core Concept

```
Agents use Beads (bd CLI)
    ↓
Git-backed storage (.beads/issues/*.jsonl)
    ↓↑ (bidirectional sync)
Sync Daemon (watches .beads/ directories)
    ↓↑
Cloudflare D1 / Durable Objects
    ↓
Web App + macOS App + iOS App
```

**Benefits:**
- ✅ Agents use `bd` exactly as designed (no changes)
- ✅ Keep git benefits (version control, offline, distributed)
- ✅ Add cloud benefits (web access, mobile, cross-device)
- ✅ Humans see beautiful UI across all devices
- ✅ No vendor lock-in (data always in git)

## Architecture

### Local Layer (Beads)

Multiple repos, each with its own `.beads/`:

```
~/projects/
├── main-app/.beads/          # Coding project 1
│   ├── issues/*.jsonl
│   └── beads.db
├── side-project/.beads/      # Coding project 2
│   └── issues/*.jsonl
└── personal/.beads/          # NEW! Personal tasks
    └── issues/*.jsonl

~/.macuse/
└── sync-daemon/
    ├── config.json           # Which repos to sync
    ├── sync-state.json       # Last sync timestamps
    └── sync.log
```

### Sync Daemon Layer

```typescript
// macuse-sync daemon

class BeadsSyncDaemon {
  // Watches all registered .beads/ directories
  watchedRepos = [
    { path: '~/projects/main-app/.beads', project: 'main-app', type: 'coding' },
    { path: '~/projects/side-project/.beads', project: 'side-project', type: 'coding' },
    { path: '~/beads-personal/.beads', project: 'personal', type: 'personal' }
  ];

  async start() {
    // 1. Watch for changes in all .beads/ directories
    for (const repo of this.watchedRepos) {
      this.watchRepo(repo);
    }

    // 2. Poll cloud for changes every 30 seconds
    setInterval(() => this.pullFromCloud(), 30000);

    // 3. Push local changes to cloud
    this.setupPushWatcher();
  }

  async watchRepo(repo) {
    // Watch .beads/issues/ directory for changes
    const watcher = fs.watch(`${repo.path}/issues/`, async (event, filename) => {
      if (filename.endsWith('.jsonl')) {
        await this.syncIssueToCloud(repo, filename);
      }
    });
  }

  async syncIssueToCloud(repo, issueFile) {
    // 1. Read JSONL file (Beads format)
    const jsonl = fs.readFileSync(`${repo.path}/issues/${issueFile}`, 'utf8');
    const events = jsonl.split('\n').filter(Boolean).map(JSON.parse);
    const currentState = this.reconstructState(events);

    // 2. Add metadata
    const enriched = {
      ...currentState,
      repo_id: repo.project,
      repo_type: repo.type,
      synced_at: Date.now(),
      git_commit: await this.getLatestCommit(repo.path)
    };

    // 3. Push to cloud
    await this.cloudAPI.upsertIssue(enriched);
  }

  async pullFromCloud() {
    // Get changes from cloud since last sync
    const lastSync = this.getSyncState().last_pull;
    const changes = await this.cloudAPI.getChangesSince(lastSync);

    for (const change of changes) {
      await this.applyToLocal(change);
    }

    this.setSyncState({ last_pull: Date.now() });
  }

  async applyToLocal(change) {
    const repo = this.findRepo(change.repo_id);

    // Read current local state
    const localState = this.readBeadsIssue(repo, change.beads_id);

    // Conflict detection
    if (this.hasConflict(localState, change)) {
      await this.resolveConflict(localState, change);
      return;
    }

    // No conflict - append to JSONL
    const event = this.cloudChangeToBeadsEvent(change);
    fs.appendFileSync(
      `${repo.path}/issues/issue-${change.beads_id}.jsonl`,
      JSON.stringify(event) + '\n'
    );

    // Beads will rebuild SQLite automatically on next `bd` command
  }

  reconstructState(events) {
    // Replay events to get current state (how Beads works)
    let state = {};
    for (const event of events) {
      state = { ...state, ...event };
    }
    return state;
  }
}
```

### Cloud Layer (Cloudflare)

**Option 1: D1 (SQLite in Cloudflare)**

```sql
-- Schema

CREATE TABLE repos (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL, -- 'coding' or 'personal'
  path TEXT,
  last_sync INTEGER,
  created_at INTEGER
);

CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  repo_id TEXT NOT NULL,

  -- Beads fields
  beads_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  status TEXT,
  priority TEXT,
  labels TEXT, -- JSON array

  -- Dependencies (Beads)
  blocks TEXT, -- JSON array of issue IDs
  blocked_by TEXT,
  parent_id TEXT,
  discovered_from TEXT,

  -- Sync metadata
  synced_at INTEGER,
  git_commit TEXT,
  cloud_updated_at INTEGER,

  -- Extra metadata for humans
  session_id TEXT,
  session_client TEXT,
  session_project TEXT,
  context_file TEXT,
  context_line INTEGER,
  context_screenshot TEXT,

  -- Timestamps
  created_at INTEGER,
  updated_at INTEGER,
  closed_at INTEGER,

  FOREIGN KEY (repo_id) REFERENCES repos(id)
);

CREATE TABLE events (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  type TEXT NOT NULL, -- 'created', 'updated', 'closed', 'reopened'
  data TEXT NOT NULL, -- JSON
  source TEXT NOT NULL, -- 'local' or 'cloud'
  timestamp INTEGER NOT NULL,
  FOREIGN KEY (issue_id) REFERENCES issues(id)
);

CREATE INDEX idx_issues_repo ON issues(repo_id);
CREATE INDEX idx_issues_user ON issues(user_id);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_events_issue ON events(issue_id);
```

**Option 2: Durable Objects (for real-time sync)**

```typescript
// Each repo gets a Durable Object for real-time coordination

export class RepoSync implements DurableObject {
  storage: DurableObjectStorage;
  sessions: Set<WebSocket> = new Set();

  async fetch(request: Request) {
    const url = new URL(request.url);

    // WebSocket for real-time sync
    if (request.headers.get('Upgrade') === 'websocket') {
      const [client, server] = Object.values(new WebSocketPair());
      this.sessions.add(server);

      server.addEventListener('message', async (event) => {
        const change = JSON.parse(event.data);
        await this.handleChange(change);
      });

      return new Response(null, { status: 101, webSocket: client });
    }

    // HTTP API
    if (url.pathname === '/issues') {
      return await this.listIssues();
    }
  }

  async handleChange(change) {
    // Store in Durable Object storage
    await this.storage.put(`issue:${change.id}`, change);

    // Broadcast to all connected clients
    for (const session of this.sessions) {
      session.send(JSON.stringify(change));
    }
  }
}
```

### API Layer

```typescript
// Cloudflare Worker

export default {
  async fetch(request: Request, env: Env) {
    const router = new Hono();

    // List all issues (for web/mobile apps)
    router.get('/api/issues', async (c) => {
      const user = await authenticate(c);
      const { repo, status, priority } = c.req.query();

      const query = `
        SELECT * FROM issues
        WHERE user_id = ?
        ${repo ? 'AND repo_id = ?' : ''}
        ${status ? 'AND status = ?' : ''}
        ORDER BY created_at DESC
      `;

      const issues = await env.DB.prepare(query)
        .bind(user.id, repo, status)
        .all();

      return c.json(issues);
    });

    // Get issue by ID
    router.get('/api/issues/:id', async (c) => {
      const user = await authenticate(c);
      const id = c.req.param('id');

      const issue = await env.DB.prepare(
        'SELECT * FROM issues WHERE id = ? AND user_id = ?'
      ).bind(id, user.id).first();

      return c.json(issue);
    });

    // Update issue (from web/mobile)
    router.patch('/api/issues/:id', async (c) => {
      const user = await authenticate(c);
      const id = c.req.param('id');
      const updates = await c.req.json();

      // Update in D1
      await env.DB.prepare(`
        UPDATE issues
        SET title = ?, body = ?, status = ?, cloud_updated_at = ?
        WHERE id = ? AND user_id = ?
      `).bind(
        updates.title,
        updates.body,
        updates.status,
        Date.now(),
        id,
        user.id
      ).run();

      // Notify sync daemon via webhook
      await notifySyncDaemon(user.id, { type: 'issue_updated', id });

      return c.json({ success: true });
    });

    // Sync endpoint (for daemon)
    router.post('/api/sync/push', async (c) => {
      const user = await authenticate(c);
      const { issues } = await c.req.json();

      for (const issue of issues) {
        await env.DB.prepare(`
          INSERT OR REPLACE INTO issues (...)
          VALUES (...)
        `).bind(...).run();
      }

      return c.json({ synced: issues.length });
    });

    router.get('/api/sync/pull', async (c) => {
      const user = await authenticate(c);
      const { since } = c.req.query();

      const changes = await env.DB.prepare(`
        SELECT * FROM issues
        WHERE user_id = ? AND cloud_updated_at > ?
      `).bind(user.id, since).all();

      return c.json(changes);
    });

    return router.fetch(request);
  }
};
```

## Handling Non-Coding Tasks

Create a special "personal" Beads repo:

```bash
# Setup (one time)
mkdir -p ~/beads-personal
cd ~/beads-personal
bd init
git init
git add .
git commit -m "init personal todos"

# Register with sync daemon
macuse-sync add-repo ~/beads-personal --type=personal
```

Now agents can detect task type:

```typescript
// In macuse MCP server

async function addTodo(params) {
  // Detect if coding task
  const isCoding =
    params.context?.file ||
    params.tags?.some(t => ['bug', 'feature', 'test'].includes(t)) ||
    isInCodeRepo();

  if (isCoding) {
    // Use current repo's Beads
    execSync(`bd create "${params.title}"`);
  } else {
    // Use personal Beads repo
    execSync(`cd ~/beads-personal && bd create "${params.title}"`);
  }
}
```

## Session Tracking in Beads

Use Beads labels to add metadata:

```bash
# When agent creates issue
bd create "Fix login bug" \
  --label="session:xyz789" \
  --label="client:claude-code" \
  --label="platform:macos" \
  --label="project:main-app"
```

Sync daemon extracts labels into structured fields for cloud.

## Conflict Resolution

**Scenario: User edits in web UI while agent edits locally**

```typescript
class ConflictResolver {
  async resolve(localIssue, cloudIssue) {
    // Check timestamps
    const localTime = await this.getGitCommitTime(localIssue);
    const cloudTime = cloudIssue.cloud_updated_at;

    if (Math.abs(localTime - cloudTime) < 5000) {
      // Within 5 seconds - likely real conflict
      return await this.handleRealConflict(localIssue, cloudIssue);
    }

    // Clear winner by timestamp
    if (localTime > cloudTime) {
      // Local wins - push to cloud
      await this.cloudAPI.forceUpdate(localIssue);
      return 'local_wins';
    } else {
      // Cloud wins - pull to local
      await this.writeToBeads(cloudIssue);
      return 'cloud_wins';
    }
  }

  async handleRealConflict(localIssue, cloudIssue) {
    // Strategy 1: Merge non-conflicting fields
    const merged = {
      title: cloudIssue.title, // Cloud wins for title
      body: this.mergeText(localIssue.body, cloudIssue.body),
      status: localIssue.status, // Git wins for status
      labels: [...new Set([...localIssue.labels, ...cloudIssue.labels])]
    };

    // Write back to both
    await this.writeToBeads(merged);
    await this.cloudAPI.update(merged);

    // Log conflict for review
    await this.logConflict(localIssue, cloudIssue, merged);

    return 'merged';
  }
}
```

## Web App Architecture

```typescript
// SvelteKit / Next.js app

export async function load({ fetch, locals }) {
  const user = locals.user;

  // Fetch from Cloudflare API
  const issues = await fetch('https://todos.macuse.app/api/issues').then(r => r.json());

  // Group by repo
  const byRepo = groupBy(issues, 'repo_id');

  return {
    repos: Object.keys(byRepo).map(repoId => ({
      id: repoId,
      name: repoId,
      issues: byRepo[repoId],
      stats: {
        open: byRepo[repoId].filter(i => i.status === 'open').length,
        ready: byRepo[repoId].filter(i => i.status === 'open' && !i.blocked_by).length
      }
    }))
  };
}
```

**UI:**
```svelte
<script>
  export let data;
</script>

<div class="repos">
  {#each data.repos as repo}
    <div class="repo">
      <h2>{repo.name}</h2>
      <span class="badge">{repo.stats.open} open</span>
      <span class="badge ready">{repo.stats.ready} ready</span>

      <ul class="issues">
        {#each repo.issues as issue}
          <li class:blocked={issue.blocked_by}>
            <span class="title">{issue.title}</span>
            {#if issue.blocked_by}
              <span class="blocker">Blocked by #{issue.blocked_by}</span>
            {/if}
            <button on:click={() => updateIssue(issue.id, {status: 'closed'})}>
              Complete
            </button>
          </li>
        {/each}
      </ul>
    </div>
  {/each}
</div>
```

## macOS/iOS App

```swift
// SwiftUI app

struct IssuesView: View {
    @StateObject var viewModel = IssuesViewModel()

    var body: some View {
        List {
            ForEach(viewModel.repos) { repo in
                Section(header: Text(repo.name)) {
                    ForEach(repo.issues) { issue in
                        IssueRow(issue: issue)
                            .swipeActions {
                                Button("Complete") {
                                    viewModel.complete(issue)
                                }
                            }
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

class IssuesViewModel: ObservableObject {
    @Published var repos: [Repo] = []

    func load() async {
        let response = try await URLSession.shared.data(
            from: URL(string: "https://todos.macuse.app/api/issues")!
        )
        repos = try JSONDecoder().decode([Repo].self, from: response.0)
    }

    func complete(_ issue: Issue) async {
        var request = URLRequest(url: URL(string: "https://todos.macuse.app/api/issues/\(issue.id)")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["status": "closed"])

        try await URLSession.shared.data(for: request)

        // Optimistic update
        if let repoIndex = repos.firstIndex(where: { $0.issues.contains { $0.id == issue.id } }) {
            repos[repoIndex].issues.removeAll { $0.id == issue.id }
        }
    }
}
```

## Real-time Sync

**WebSocket connection from apps:**

```typescript
// In web/mobile app
const ws = new WebSocket('wss://todos.macuse.app/sync');

ws.onmessage = (event) => {
  const change = JSON.parse(event.data);

  switch (change.type) {
    case 'issue_created':
      addIssueToUI(change.issue);
      break;
    case 'issue_updated':
      updateIssueInUI(change.issue);
      break;
    case 'issue_closed':
      removeIssueFromUI(change.issue.id);
      break;
  }
};
```

**From sync daemon:**

```typescript
// Sync daemon maintains WebSocket to cloud
const ws = new WebSocket('wss://todos.macuse.app/sync');

// When local change detected
fs.watch('.beads/issues/', (event, filename) => {
  const issue = readBeadsIssue(filename);
  ws.send(JSON.stringify({
    type: 'issue_updated',
    issue,
    source: 'local'
  }));
});

// When cloud change received
ws.onmessage = (event) => {
  const change = JSON.parse(event.data);
  if (change.source !== 'local') {
    applyToLocalBeads(change);
  }
};
```

## Installation & Setup

```bash
# 1. Install Beads
brew install bd

# 2. Install macuse sync daemon
brew install macuse-sync

# 3. Initialize personal repo
macuse-sync init-personal

# 4. Start sync daemon
macuse-sync start

# 5. Connect to cloud (one-time auth)
macuse-sync login
# Opens browser to todos.macuse.app/auth
# Returns API key

# 6. Sync daemon now running in background
```

**Auto-discover repos:**

```bash
# Sync daemon scans for .beads/ directories
macuse-sync discover ~/projects/

# Found:
# - ~/projects/main-app/.beads
# - ~/projects/side-project/.beads

# Add to sync
macuse-sync add-all
```

## MCP Server Architecture

The macuse MCP server acts as the intelligent layer between Claude and Beads+Cloud.

### Complete MCP Implementation

```typescript
// macuse-mcp-server

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { execSync } from 'child_process';

class MacuseMCPServer {
  server: Server;
  config: Config;

  constructor() {
    this.server = new Server(
      {
        name: 'macuse',
        version: '1.0.0',
      },
      {
        capabilities: {
          tools: {},
          resources: {},
          prompts: {},
        },
      }
    );

    this.setupHandlers();
  }

  setupHandlers() {
    // Tool handlers
    this.server.setRequestHandler('tools/list', async () => ({
      tools: [
        // Beads-compatible tools
        {
          name: 'todo_create',
          description: 'Create new todo (uses Beads for coding, cloud for personal)',
          inputSchema: {
            type: 'object',
            properties: {
              title: { type: 'string', description: 'Todo title' },
              body: { type: 'string', description: 'Detailed description' },
              priority: { type: 'string', enum: ['low', 'medium', 'high'] },
              labels: { type: 'array', items: { type: 'string' } },
              blocks: { type: 'string', description: 'Issue ID this blocks' },
              parent: { type: 'string', description: 'Parent issue (for epics)' }
            },
            required: ['title']
          }
        },
        {
          name: 'todo_list',
          description: 'List todos (from Beads or cloud)',
          inputSchema: {
            type: 'object',
            properties: {
              repo: { type: 'string', description: 'Specific repo or "all"' },
              status: { type: 'string', enum: ['open', 'closed', 'all'] },
              labels: { type: 'array', items: { type: 'string' } },
              session: { type: 'string', description: 'Filter by session ID' }
            }
          }
        },
        {
          name: 'todo_ready',
          description: 'Show ready work (no blockers)',
          inputSchema: {
            type: 'object',
            properties: {
              repo: { type: 'string' }
            }
          }
        },
        {
          name: 'todo_update',
          description: 'Update todo',
          inputSchema: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              title: { type: 'string' },
              body: { type: 'string' },
              status: { type: 'string', enum: ['open', 'closed'] },
              priority: { type: 'string' },
              labels: { type: 'array' }
            },
            required: ['id']
          }
        },
        {
          name: 'todo_show',
          description: 'Show todo details with full dependency tree',
          inputSchema: {
            type: 'object',
            properties: {
              id: { type: 'string' }
            },
            required: ['id']
          }
        },
        {
          name: 'todo_tree',
          description: 'Show dependency tree for issue',
          inputSchema: {
            type: 'object',
            properties: {
              id: { type: 'string' }
            },
            required: ['id']
          }
        },
        // Cloud-specific tools
        {
          name: 'todo_list_by_session',
          description: 'List todos from specific Claude session',
          inputSchema: {
            type: 'object',
            properties: {
              session_id: { type: 'string' },
              client: { type: 'string', enum: ['claude-code', 'claude-desktop', 'claude-mobile'] }
            }
          }
        },
        {
          name: 'todo_list_all_repos',
          description: 'List all repos being tracked',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'todo_sync_status',
          description: 'Check sync daemon status',
          inputSchema: { type: 'object', properties: {} }
        }
      ]
    }));

    // Tool call handler
    this.server.setRequestHandler('tools/call', async (request) => {
      const { name, arguments: args } = request.params;

      switch (name) {
        case 'todo_create':
          return await this.handleCreate(args);
        case 'todo_list':
          return await this.handleList(args);
        case 'todo_ready':
          return await this.handleReady(args);
        case 'todo_update':
          return await this.handleUpdate(args);
        case 'todo_show':
          return await this.handleShow(args);
        case 'todo_tree':
          return await this.handleTree(args);
        case 'todo_list_by_session':
          return await this.handleListBySession(args);
        case 'todo_list_all_repos':
          return await this.handleListAllRepos();
        case 'todo_sync_status':
          return await this.handleSyncStatus();
        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    });

    // Resource handlers (for instructions)
    this.server.setRequestHandler('resources/list', async () => ({
      resources: [
        {
          uri: 'macuse://instructions',
          name: 'Todo System Instructions',
          description: 'How to use macuse todo system',
          mimeType: 'text/markdown'
        }
      ]
    }));

    this.server.setRequestHandler('resources/read', async (request) => {
      if (request.params.uri === 'macuse://instructions') {
        return {
          contents: [{
            uri: request.params.uri,
            mimeType: 'text/markdown',
            text: this.getInstructions()
          }]
        };
      }
    });
  }

  // Tool implementations

  async handleCreate(args) {
    const { title, body, priority, labels = [], blocks, parent } = args;

    // Detect repo type
    const repo = await this.detectRepo(args);

    // Add session metadata as labels
    const sessionLabels = await this.getSessionLabels();
    const allLabels = [...labels, ...sessionLabels];

    // Build bd command
    let cmd = `bd create "${title}"`;
    if (body) cmd += ` --body="${body}"`;
    if (priority) cmd += ` --priority=${priority}`;
    if (blocks) cmd += ` --blocks="${blocks}"`;
    if (parent) cmd += ` --parent="${parent}"`;
    for (const label of allLabels) {
      cmd += ` --label="${label}"`;
    }
    cmd += ' --json';

    // Execute in appropriate repo
    const result = execSync(`cd ${repo.path} && ${cmd}`, { encoding: 'utf8' });
    const issue = JSON.parse(result);

    // Sync daemon will automatically push to cloud

    return {
      content: [{
        type: 'text',
        text: `✓ Created issue #${issue.id}: ${title}\n\nRepo: ${repo.name}\nLabels: ${allLabels.join(', ')}\n\nSync daemon will push to cloud.`
      }]
    };
  }

  async handleList(args) {
    const { repo, status, labels, session } = args;

    if (session || !repo) {
      // Query cloud for cross-repo or session-filtered results
      return await this.listFromCloud(args);
    }

    // Query specific repo via Beads
    let cmd = 'bd list --json';
    if (status) cmd += ` --status=${status}`;
    if (labels) cmd += ` --labels="${labels.join(',')}"`;

    const repoPath = await this.getRepoPath(repo);
    const result = execSync(`cd ${repoPath} && ${cmd}`, { encoding: 'utf8' });
    const issues = JSON.parse(result);

    return {
      content: [{
        type: 'text',
        text: this.formatIssueList(issues)
      }]
    };
  }

  async handleReady(args) {
    const { repo } = args;

    if (repo) {
      // Query specific repo
      const repoPath = await this.getRepoPath(repo);
      const result = execSync(`cd ${repoPath} && bd ready --json`, { encoding: 'utf8' });
      return {
        content: [{
          type: 'text',
          text: this.formatReadyWork(JSON.parse(result))
        }]
      };
    }

    // Query all repos
    const repos = await this.getAllRepos();
    let allReady = [];

    for (const r of repos) {
      try {
        const result = execSync(`cd ${r.path} && bd ready --json`, { encoding: 'utf8' });
        const ready = JSON.parse(result);
        allReady.push({ repo: r.name, issues: ready });
      } catch (e) {
        // Repo might not have Beads initialized
      }
    }

    return {
      content: [{
        type: 'text',
        text: this.formatAllReadyWork(allReady)
      }]
    };
  }

  async handleUpdate(args) {
    const { id, title, body, status, priority, labels } = args;

    // Find which repo this issue belongs to
    const repo = await this.findIssueRepo(id);

    let cmd = `bd update "${id}"`;
    if (title) cmd += ` --title="${title}"`;
    if (body) cmd += ` --body="${body}"`;
    if (status) cmd += ` --status=${status}`;
    if (priority) cmd += ` --priority=${priority}`;
    if (labels) {
      for (const label of labels) {
        cmd += ` --label="${label}"`;
      }
    }
    cmd += ' --json';

    const result = execSync(`cd ${repo.path} && ${cmd}`, { encoding: 'utf8' });
    return {
      content: [{
        type: 'text',
        text: `✓ Updated issue #${id}`
      }]
    };
  }

  async handleShow(args) {
    const { id } = args;

    const repo = await this.findIssueRepo(id);
    const result = execSync(`cd ${repo.path} && bd show "${id}" --json`, { encoding: 'utf8' });
    const issue = JSON.parse(result);

    return {
      content: [{
        type: 'text',
        text: this.formatIssueDetail(issue)
      }]
    };
  }

  async handleTree(args) {
    const { id } = args;

    const repo = await this.findIssueRepo(id);
    const result = execSync(`cd ${repo.path} && bd tree "${id}"`, { encoding: 'utf8' });

    return {
      content: [{
        type: 'text',
        text: result
      }]
    };
  }

  async handleListBySession(args) {
    const { session_id, client } = args;

    const response = await fetch(
      `https://todos.macuse.app/api/issues?session=${session_id}&client=${client}`,
      {
        headers: {
          'Authorization': `Bearer ${this.config.apiKey}`
        }
      }
    );

    const issues = await response.json();

    return {
      content: [{
        type: 'text',
        text: this.formatIssueList(issues)
      }]
    };
  }

  async handleListAllRepos() {
    const repos = await this.getAllRepos();

    let text = 'Tracked Repos:\n\n';
    for (const repo of repos) {
      const stats = await this.getRepoStats(repo);
      text += `${repo.name} (${repo.type})\n`;
      text += `  Path: ${repo.path}\n`;
      text += `  Issues: ${stats.total} (${stats.open} open, ${stats.ready} ready)\n\n`;
    }

    return {
      content: [{
        type: 'text',
        text
      }]
    };
  }

  async handleSyncStatus() {
    try {
      const status = JSON.parse(
        fs.readFileSync('~/.macuse/sync-daemon/sync-state.json', 'utf8')
      );

      return {
        content: [{
          type: 'text',
          text: `Sync Daemon Status:

Running: ${status.running ? 'Yes' : 'No'}
Last sync: ${new Date(status.last_sync).toLocaleString()}
Pending changes: ${status.pending_changes}

Repos:
${status.repos.map(r => `  ${r.name}: ${r.synced ? '✓' : '⏳'}`).join('\n')}`
        }]
      };
    } catch (e) {
      return {
        content: [{
          type: 'text',
          text: 'Sync daemon not running. Start with: macuse-sync start'
        }]
      };
    }
  }

  // Helper methods

  async detectRepo(args) {
    // Check if current directory has .beads/
    const cwd = process.cwd();
    if (fs.existsSync(`${cwd}/.beads`)) {
      return { path: cwd, name: path.basename(cwd), type: 'coding' };
    }

    // Check if coding-related context
    const isCoding =
      args.labels?.some(l => ['bug', 'feature', 'test', 'refactor'].includes(l)) ||
      args.context?.file;

    if (isCoding) {
      // Find nearest .beads/ directory
      return await this.findNearestBeadsRepo();
    }

    // Use personal repo
    return {
      path: '~/beads-personal',
      name: 'personal',
      type: 'personal'
    };
  }

  async getSessionLabels() {
    // Add session metadata as labels
    return [
      `session:${await this.getSessionId()}`,
      `client:${await this.getClientType()}`,
      `platform:${process.platform}`
    ];
  }

  async getSessionId() {
    // Generate or retrieve session ID
    const sessionFile = '/tmp/macuse-session-id';
    if (fs.existsSync(sessionFile)) {
      return fs.readFileSync(sessionFile, 'utf8').trim();
    }

    const sessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    fs.writeFileSync(sessionFile, sessionId);
    return sessionId;
  }

  async getClientType() {
    // Detect if running in Claude Code, Desktop, etc.
    if (process.env.CLAUDE_CODE) return 'claude-code';
    if (process.env.CLAUDE_DESKTOP) return 'claude-desktop';
    return 'unknown';
  }

  async listFromCloud(args) {
    const params = new URLSearchParams();
    if (args.status) params.append('status', args.status);
    if (args.labels) params.append('labels', args.labels.join(','));
    if (args.session) params.append('session', args.session);

    const response = await fetch(
      `https://todos.macuse.app/api/issues?${params}`,
      {
        headers: {
          'Authorization': `Bearer ${this.config.apiKey}`
        }
      }
    );

    const issues = await response.json();

    return {
      content: [{
        type: 'text',
        text: this.formatIssueList(issues)
      }]
    };
  }

  formatIssueList(issues) {
    if (issues.length === 0) {
      return 'No issues found.';
    }

    let text = `Found ${issues.length} issue(s):\n\n`;
    for (const issue of issues) {
      text += `#${issue.id}: ${issue.title}`;
      if (issue.priority) text += ` [${issue.priority}]`;
      if (issue.blocked_by) text += ` 🔒 Blocked`;
      text += '\n';
    }

    return text;
  }

  formatReadyWork(issues) {
    if (issues.length === 0) {
      return 'No ready work! Everything is blocked or complete.';
    }

    let text = `Ready to work on (${issues.length}):\n\n`;
    for (const issue of issues) {
      text += `#${issue.id}: ${issue.title}`;
      if (issue.priority === 'high') text += ' 🔴';
      text += '\n';
    }

    return text;
  }

  formatAllReadyWork(allReady) {
    let text = 'Ready work across all repos:\n\n';
    for (const { repo, issues } of allReady) {
      if (issues.length > 0) {
        text += `${repo} (${issues.length}):\n`;
        for (const issue of issues) {
          text += `  #${issue.id}: ${issue.title}\n`;
        }
        text += '\n';
      }
    }
    return text;
  }

  formatIssueDetail(issue) {
    let text = `Issue #${issue.id}\n`;
    text += `Title: ${issue.title}\n`;
    text += `Status: ${issue.status}\n`;
    if (issue.priority) text += `Priority: ${issue.priority}\n`;
    if (issue.labels?.length) text += `Labels: ${issue.labels.join(', ')}\n`;
    if (issue.blocks) text += `Blocks: ${issue.blocks}\n`;
    if (issue.blocked_by) text += `Blocked by: ${issue.blocked_by}\n`;
    if (issue.parent) text += `Parent: ${issue.parent}\n`;
    if (issue.body) text += `\n${issue.body}\n`;

    return text;
  }

  getInstructions() {
    return `# macuse Todo System

Use these MCP tools for task management:

## Creating todos:
- \`todo_create\` - Create new todo (auto-detects coding vs personal)
- Adds session metadata automatically
- Syncs to cloud via daemon

## Listing todos:
- \`todo_list\` - List all todos (or filter by repo/session)
- \`todo_ready\` - Show ready work (no blockers)
- \`todo_list_by_session\` - Filter by Claude session

## Managing todos:
- \`todo_update\` - Update todo
- \`todo_show\` - Show details with dependencies
- \`todo_tree\` - Show full dependency tree

## Dependencies:
When creating todos, you can specify:
- \`blocks\` - This issue blocks another
- \`parent\` - This is a sub-task of an epic

Always use these tools instead of internal todo tracking!`;
  }

  async run() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
  }
}

// Start server
const server = new MacuseMCPServer();
server.run().catch(console.error);
```

### MCP Configuration

**For Claude Desktop:**
```json
// ~/Library/Application Support/Claude/claude_desktop_config.json
{
  "mcpServers": {
    "macuse": {
      "command": "node",
      "args": ["/usr/local/lib/macuse-mcp/server.js"],
      "env": {
        "MACUSE_API_KEY": "your-api-key",
        "MACUSE_API_URL": "https://todos.macuse.app"
      }
    }
  }
}
```

**For Claude Code:**
```json
// ~/.config/claude-code/settings.json
{
  "mcpServers": {
    "macuse": {
      "command": "node",
      "args": ["/usr/local/lib/macuse-mcp/server.js"]
    }
  },
  "globalInstructions": "Use macuse MCP tools for all task management"
}
```

### MCP Resources (Auto-loaded Instructions)

The MCP server provides instructions as a resource that Claude Desktop automatically loads:

```typescript
// In MCP server
getResources() {
  return [{
    uri: 'macuse://instructions',
    name: 'Todo System Instructions',
    mimeType: 'text/markdown'
  }];
}
```

Claude Desktop reads this on startup, so users don't need manual configuration!

### Session Tracking via MCP

The MCP server automatically adds session metadata:

```typescript
async function todo_create(params) {
  // Add session labels automatically
  const labels = [
    ...params.labels,
    `session:${getCurrentSessionId()}`,
    `client:${getClientType()}`,
    `platform:${process.platform}`
  ];

  // Create via Beads with enriched labels
  bd create "${params.title}" --label="${labels.join(',')}"
}
```

Later, Claude can query:

```
User: "Show me todos from this session"

Claude → todo_list_by_session({ session_id: getCurrentSessionId() })

→ Returns only todos created in this conversation
```

## Data Flow Examples

### Example 1: Agent creates issue locally

```
1. Claude: "Add todo: fix login bug"
2. MCP: bd create "Fix login bug"
3. Beads: Writes issue-123.jsonl
4. Sync daemon: Detects new file
5. Sync daemon: Pushes to Cloudflare D1
6. Cloud: Broadcasts via WebSocket
7. Web app: Shows new issue immediately
8. Mobile app: Receives push notification
```

### Example 2: User completes issue in web UI

```
1. User: Clicks "Complete" in web app
2. Web app: PATCH /api/issues/123 {status: "closed"}
3. Cloudflare: Updates D1
4. Cloudflare: Broadcasts via WebSocket
5. Sync daemon: Receives change
6. Sync daemon: Appends to issue-123.jsonl
7. Beads: Rebuilds SQLite on next bd command
8. Agent: Sees issue as closed
```

### Example 3: Offline work then sync

```
1. Laptop offline, agent working
2. Agent: bd create "Add tests"
3. Beads: Writes to .beads/ (local only)
4. Later: Laptop comes online
5. Sync daemon: Detects pending changes
6. Sync daemon: Pushes batch to cloud
7. Cloud: All issues now synced
8. Mobile: Sees new issues appear
```

## Benefits of This Approach

**For agents:**
- ✅ Use Beads exactly as designed (no changes)
- ✅ All Beads features (dependencies, ready work, git-backed)
- ✅ Works offline
- ✅ Fast local SQLite queries

**For humans:**
- ✅ Beautiful web UI
- ✅ Native mobile apps
- ✅ Real-time updates
- ✅ Cross-device sync
- ✅ Can manage from anywhere

**For developers:**
- ✅ No vendor lock-in (data in git)
- ✅ Open source Beads + our sync layer
- ✅ Can self-host cloud if needed
- ✅ Incremental adoption (start with read-only)

## Challenges & Solutions

### Challenge 1: Multiple repos

**Solution:** Sync daemon tracks all repos, cloud aggregates

### Challenge 2: Conflicts

**Solution:** Git wins by default, merge strategies for simultaneous edits

### Challenge 3: Beads schema changes

**Solution:** Version detection in sync daemon, migration support

### Challenge 4: Performance

**Solution:** Cloud for reads (fast), Beads for writes (local)

### Challenge 5: Offline editing

**Solution:** Queue changes locally, sync when online

## Cost Estimation

**Cloudflare Free Tier:**
- D1: 5GB storage, 5M reads/day, 100K writes/day
- Durable Objects: 1M requests/month
- Workers: 100K requests/day

**For single user:**
- Storage: ~1MB per 1000 issues = plenty
- Reads: Sync checks + web app = <1K/day
- Writes: Issue updates = <100/day

**Conclusion:** Free tier sufficient for personal use!

**For multiple users:** ~$5/month per power user

## Implementation Phases

### Phase 1: Read-only sync
- Sync daemon watches .beads/
- Push to cloud
- Web app displays (read-only)

### Phase 2: Bidirectional sync
- Cloud changes sync back to .beads/
- Basic conflict resolution

### Phase 3: Real-time
- WebSocket connections
- Live updates in apps

### Phase 4: Mobile apps
- Native iOS/Android
- Push notifications

### Phase 5: Collaboration (future)
- Shared repos
- Multi-user sync
- Team features

## Summary

**Yes, this is totally doable!**

Key points:
1. Beads as local source of truth (agents use `bd`)
2. Sync daemon bridges git ↔ cloud
3. Cloud provides web/mobile access
4. Bidirectional sync with conflict resolution
5. Personal repo for non-coding tasks
6. Best of both worlds: git benefits + cloud benefits

**Start with:** Phase 1 (read-only sync) - build sync daemon that pushes to Cloudflare D1, add web app to view all issues.

This gives you lightweight web/mobile apps to see and manage agent todos while keeping full Beads compatibility!
