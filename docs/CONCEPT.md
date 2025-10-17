# BeadsHub - GitHub for bd (Beads Issue Tracker)

## Vision

**bd is to Git what BeadsHub is to GitHub**

Beads (`bd`) is a local git-backed issue tracker for AI agents.
BeadsHub is the cloud platform to view, manage, and sync all your Beads issues across devices.

## Core Insight

You have:
- 30+ coding projects (each with `.beads/`)
- Personal tasks (no specific repo)
- Company work
- NGO projects
- Random sessions in Claude Code/Desktop

**Problem:** How do you see everything in one place? How do you access from mobile? How do you edit in a nice UI?

**Solution:** BeadsHub aggregates ALL your Beads issues and provides beautiful UIs.

## Mental Model

```
Git                    →    GitHub
Local repos            →    Cloud view of all repos
Git push/pull          →    Sync
CLI only               →    Beautiful web UI
Per-repo               →    Cross-repo search

bd (Beads)             →    BeadsHub
.beads/ directories    →    Cloud view of all issues
bd sync                →    Auto-sync daemon
CLI only               →    Web + iOS + macOS apps
Per-project            →    See ALL issues
```

## Architecture

### Local Layer (User's Machine)

```
~/projects/
├── project-a/.beads/           # Coding project 1
├── project-b/.beads/           # Coding project 2
├── company-site/.beads/        # Company work
└── ngo-website/.beads/         # NGO work

~/Documents/
└── random-ideas/.beads/        # Personal notes

# NO specific location required!
# BeadsHub finds ALL .beads/ directories
```

**Key difference from previous idea:**
- ❌ Not "coding" vs "personal" repos
- ✅ Just finds ALL `.beads/` directories on your machine
- ✅ You can have `.beads/` anywhere
- ✅ Random Claude Code sessions? Just `bd init` and issues go there

### Sync Daemon

```bash
# Install
brew install beadshub-sync

# One-time setup
beadshub login
# Authenticates with beadshub.com, gets API key

# Auto-discovery
beadshub discover
# Scans entire home directory for .beads/
# Found: ~/projects/project-a/.beads
# Found: ~/projects/project-b/.beads
# Found: ~/Documents/random-ideas/.beads
# ... etc

# Start daemon (runs in background)
beadshub sync start
# Watches all .beads/ directories
# Syncs changes to cloud
```

**What it does:**
1. Watches ALL `.beads/` directories for changes
2. Pushes new/updated issues to cloud
3. Pulls changes from cloud (if you edit in web UI)
4. Works even if you create new `.beads/` directories

### Cloud Layer (BeadsHub)

**Infrastructure:** Cloudflare Workers + D1

```sql
-- Database schema

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  api_key TEXT UNIQUE NOT NULL,
  created_at INTEGER
);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  -- Source info
  name TEXT,              -- "project-a", "random-ideas"
  type TEXT,              -- "auto-detected", "manual", "session"
  path TEXT,              -- Original path on user's machine (for reference)
  machine_id TEXT,        -- Which computer
  -- Metadata
  first_seen INTEGER,
  last_sync INTEGER,
  issue_count INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,

  -- Beads fields (from bd)
  beads_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  status TEXT NOT NULL,
  priority TEXT,
  labels TEXT,            -- JSON array

  -- Dependencies (Beads native)
  blocks TEXT,            -- JSON array
  blocked_by TEXT,        -- JSON array
  parent_id TEXT,
  discovered_from TEXT,

  -- Sync metadata
  synced_at INTEGER,
  cloud_updated_at INTEGER,

  -- Timestamps
  created_at INTEGER,
  updated_at INTEGER,
  closed_at INTEGER,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id)
);

CREATE INDEX idx_issues_user ON issues(user_id);
CREATE INDEX idx_issues_source ON issues(source_id);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_labels ON issues(labels);
```

**Key insight:** `sources` replaces "repos" - it's just "where did this issue come from?"

### API

```typescript
// Cloudflare Worker

import { Hono } from 'hono';

const app = new Hono();

// List all sources (your "projects")
app.get('/api/sources', async (c) => {
  const user = await authenticate(c);

  const sources = await env.DB.prepare(`
    SELECT
      s.*,
      COUNT(i.id) as issue_count,
      SUM(CASE WHEN i.status = 'open' THEN 1 ELSE 0 END) as open_count
    FROM sources s
    LEFT JOIN issues i ON i.source_id = s.id
    WHERE s.user_id = ?
    GROUP BY s.id
    ORDER BY s.last_sync DESC
  `).bind(user.id).all();

  return c.json(sources);
});

// List all issues (cross-source)
app.get('/api/issues', async (c) => {
  const user = await authenticate(c);
  const { source, status, labels, search } = c.req.query();

  let query = `
    SELECT i.*, s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ?
  `;

  const params = [user.id];

  if (source) {
    query += ' AND i.source_id = ?';
    params.push(source);
  }

  if (status) {
    query += ' AND i.status = ?';
    params.push(status);
  }

  if (labels) {
    // JSON search
    query += ` AND i.labels LIKE ?`;
    params.push(`%${labels}%`);
  }

  if (search) {
    query += ` AND (i.title LIKE ? OR i.body LIKE ?)`;
    params.push(`%${search}%`, `%${search}%`);
  }

  query += ' ORDER BY i.created_at DESC';

  const issues = await env.DB.prepare(query).bind(...params).all();

  return c.json(issues);
});

// Get ready work (all sources or filtered)
app.get('/api/ready', async (c) => {
  const user = await authenticate(c);
  const { source } = c.req.query();

  // Issues with no blockers
  let query = `
    SELECT i.*, s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ?
    AND i.status = 'open'
    AND (i.blocked_by IS NULL OR i.blocked_by = '[]')
  `;

  const params = [user.id];

  if (source) {
    query += ' AND i.source_id = ?';
    params.push(source);
  }

  const ready = await env.DB.prepare(query).bind(...params).all();

  return c.json(ready);
});

// Update issue (from web UI)
app.patch('/api/issues/:id', async (c) => {
  const user = await authenticate(c);
  const id = c.req.param('id');
  const updates = await c.req.json();

  // Update in database
  await env.DB.prepare(`
    UPDATE issues
    SET
      title = COALESCE(?, title),
      body = COALESCE(?, body),
      status = COALESCE(?, status),
      priority = COALESCE(?, priority),
      cloud_updated_at = ?
    WHERE id = ? AND user_id = ?
  `).bind(
    updates.title,
    updates.body,
    updates.status,
    updates.priority,
    Date.now(),
    id,
    user.id
  ).run();

  // Notify sync daemon via webhook/SSE
  await notifySyncDaemon(user.id, { type: 'issue_updated', id });

  return c.json({ success: true });
});

// Sync endpoint (daemon pushes here)
app.post('/api/sync/push', async (c) => {
  const user = await authenticate(c);
  const { source, issues } = await c.req.json();

  // Upsert source
  await env.DB.prepare(`
    INSERT INTO sources (id, user_id, name, type, path, machine_id, first_seen, last_sync)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      last_sync = ?,
      issue_count = ?
  `).bind(
    source.id,
    user.id,
    source.name,
    source.type,
    source.path,
    source.machine_id,
    Date.now(),
    Date.now(),
    Date.now(),
    issues.length
  ).run();

  // Upsert issues
  for (const issue of issues) {
    await env.DB.prepare(`
      INSERT INTO issues (...)
      VALUES (...)
      ON CONFLICT(id) DO UPDATE SET ...
    `).bind(...).run();
  }

  return c.json({ synced: issues.length });
});

// Sync endpoint (daemon pulls changes)
app.get('/api/sync/pull', async (c) => {
  const user = await authenticate(c);
  const { since } = c.req.query();

  const changes = await env.DB.prepare(`
    SELECT * FROM issues
    WHERE user_id = ? AND cloud_updated_at > ?
  `).bind(user.id, since).all();

  return c.json(changes);
});

export default app;
```

## How It Works: Real Usage

### Scenario 1: You Have 30+ Projects

```bash
# One-time setup
beadshub login
beadshub discover

# Output:
# Scanning for .beads/ directories...
#
# Found 34 sources:
# ~/projects/project-a/.beads (23 issues)
# ~/projects/project-b/.beads (5 issues)
# ~/work/company-site/.beads (12 issues)
# ~/Documents/personal/.beads (8 issues)
# ... (30 more)
#
# Total: 342 issues
#
# Start syncing? [Y/n]

beadshub sync start
# ✓ Sync daemon started
# ✓ Watching 34 sources
# ✓ Connected to beadshub.com
```

### Scenario 2: Random Claude Code Session

```bash
# You're in some random directory
cd ~/Downloads/temp-project

# Claude Code is helping you
# Agent decides to track work

Agent: bd init
# Created .beads/ in ~/Downloads/temp-project

Agent: bd create "Research XYZ library"

# Sync daemon automatically detects new .beads/
# Daemon: New source detected: temp-project
# Daemon: Syncing 1 issue to cloud
# ✓ Synced

# Now you can see it on beadshub.com!
```

### Scenario 3: View Everything

**On beadshub.com:**

```
All Issues (342)

Filters:
☐ Show closed
Sources: [All ▼]
Labels: [All ▼]

Sort: Most recent

-----------------------------------------

temp-project (1 issue)
  #1 Research XYZ library (open)

project-a (23 issues)
  #54 Fix login bug (open) 🔴
  #53 Add OAuth (blocked)
  #52 Update docs (open)
  ...

project-b (5 issues)
  #12 Deploy to prod (open)
  ...

[Show 10 more sources ▼]

-----------------------------------------

Ready to work on: 47 issues
```

### Scenario 4: Filter to One Project

```
beadshub.com/sources/project-a

Project A (23 issues, 12 open)

Ready work (3):
  #54 Fix login bug 🔴
  #55 Add rate limiting
  #56 Update tests

Blocked (2):
  #53 Add OAuth (blocked by #54)
  #57 Deploy (blocked by #53)

[Dependency Tree View] [List View] [Kanban]
```

### Scenario 5: Edit from Web

```
User clicks: #54 Fix login bug

[Issue Detail]
Title: Fix login bug
Status: [Open ▼]  Priority: [High ▼]
Labels: bug, auth

Body:
Users getting logged out randomly.
Need to investigate session handling.

Dependencies:
  Blocks: #53 Add OAuth

[Save]

# On save:
# 1. Updates cloud database
# 2. Sync daemon pulls change
# 3. Updates local .beads/issues/issue-54.jsonl
# 4. bd sees the change
```

## Handling Sources Without Repos

**Problem:** You said not all tasks live in a folder. Random Claude sessions.

**Solution:** Flexible source detection:

### Option 1: Default Personal Source

```bash
# Create a catch-all .beads/ directory
mkdir -p ~/.beadshub/personal
cd ~/.beadshub/personal
bd init

# In your MCP server config
DEFAULT_BEADS_PATH=~/.beadshub/personal
```

When Claude creates a todo in a random session (no local `.beads/`):
- MCP server uses default path
- All "homeless" issues go there
- Still synced to cloud
- You can filter by source: "personal"

### Option 2: Session-Based Sources

```bash
# MCP server creates .beads/ per session
~/.beadshub/sessions/
├── session-abc123/.beads/    # Claude Code session from Oct 15
├── session-def456/.beads/    # Claude Desktop session from Oct 16
└── session-ghi789/.beads/    # Claude Mobile session from today
```

Each Claude session gets its own `.beads/` directory.

In BeadsHub UI:
```
Sources:

session-abc123 (Claude Code, Oct 15)
  5 issues

session-def456 (Claude Desktop, Oct 16)
  2 issues

session-ghi789 (Claude Mobile, today)
  3 issues
```

### Option 3: Tag-Based (No Sources)

Don't worry about sources at all. Just use labels:

```bash
bd create "Fix bug" --label="project:project-a"
bd create "Call John" --label="personal"
bd create "Update website" --label="company"
bd create "Plan event" --label="ngo"
```

BeadsHub groups by labels, not sources.

## MCP Server Integration

### Two MCP Servers

**1. Local MCP Server (on your machine)**
- Wraps `bd` CLI
- Watches for `.beads/` directories
- Syncs to BeadsHub cloud

**2. Cloud MCP Server (BeadsHub provides)**
- Runs on Cloudflare
- Accesses your BeadsHub data via API
- For when you want cloud-first access

### Use Cases

**Local MCP (most common):**
```
Claude Code → Local MCP → bd CLI → .beads/ → Sync daemon → Cloud
```

**Cloud MCP (when needed):**
```
Claude Desktop (no local .beads/) → Cloud MCP → BeadsHub API → Database
```

### Local MCP Implementation

```typescript
// beadshub-mcp-server (runs locally)

class BeadsHubMCP {
  async todo_create(params) {
    // Find appropriate .beads/ directory
    const beadsDir = await this.findBeadsDir();

    // Build enhanced labels with session metadata
    const labels = [
      ...(params.labels || []),
      ...await this.getSessionLabels()
    ];

    // Build bd command with all metadata
    let cmd = `bd create "${params.title}"`;
    if (params.body) cmd += ` --body="${params.body}"`;
    if (params.priority) cmd += ` --priority=${params.priority}`;
    if (params.blocks) cmd += ` --blocks="${params.blocks}"`;
    if (params.parent) cmd += ` --parent="${params.parent}"`;

    // Add all labels including session metadata
    for (const label of labels) {
      cmd += ` --label="${label}"`;
    }
    cmd += ' --json';

    // Use bd CLI
    const result = execSync(`cd ${beadsDir} && ${cmd}`, { encoding: 'utf8' });

    // Sync daemon automatically picks up change

    const issue = JSON.parse(result);

    return {
      content: [{
        type: 'text',
        text: `✓ Created issue #${issue.id}: ${params.title}\n\nSource: ${path.basename(beadsDir)}\nSession: ${await this.getSessionId()}\nClient: ${await this.getClientType()}`
      }]
    };
  }

  async getSessionLabels() {
    // Auto-capture session metadata as labels
    return [
      `session:${await this.getSessionId()}`,
      `client:${await this.getClientType()}`,
      `platform:${process.platform}`,
      `project:${await this.getProjectName()}`
    ];
  }

  async getSessionId() {
    // Generate or retrieve persistent session ID for this conversation
    const sessionFile = '/tmp/beadshub-session-id';

    if (fs.existsSync(sessionFile)) {
      const data = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
      // Check if session is still active (< 24 hours old)
      if (Date.now() - data.created_at < 24 * 60 * 60 * 1000) {
        return data.session_id;
      }
    }

    // Create new session ID
    const sessionId = `session_${Date.now()}_${this.randomString(8)}`;
    fs.writeFileSync(sessionFile, JSON.stringify({
      session_id: sessionId,
      created_at: Date.now(),
      client: await this.getClientType(),
      project: await this.getProjectName()
    }));

    return sessionId;
  }

  async getClientType() {
    // Detect which Claude client is running
    if (process.env.CLAUDE_CODE) return 'claude-code';
    if (process.env.CLAUDE_DESKTOP) return 'claude-desktop';

    // Try to detect from process
    const parentProcess = process.ppid;
    try {
      const processName = execSync(`ps -p ${parentProcess} -o comm=`, { encoding: 'utf8' }).trim();
      if (processName.includes('Claude')) return 'claude-desktop';
      if (processName.includes('code')) return 'claude-code';
    } catch (e) {}

    return 'unknown';
  }

  async getProjectName() {
    const beadsDir = await this.findBeadsDir();

    // Try multiple sources in priority order:

    // 1. From package.json
    const packageJson = path.join(beadsDir, 'package.json');
    if (fs.existsSync(packageJson)) {
      const pkg = JSON.parse(fs.readFileSync(packageJson, 'utf8'));
      if (pkg.name) return pkg.name;
    }

    // 2. From Cargo.toml
    const cargoToml = path.join(beadsDir, 'Cargo.toml');
    if (fs.existsSync(cargoToml)) {
      const cargo = fs.readFileSync(cargoToml, 'utf8');
      const match = cargo.match(/name\s*=\s*"([^"]+)"/);
      if (match) return match[1];
    }

    // 3. From go.mod
    const goMod = path.join(beadsDir, 'go.mod');
    if (fs.existsSync(goMod)) {
      const mod = fs.readFileSync(goMod, 'utf8');
      const match = mod.match(/module\s+([^\s]+)/);
      if (match) return match[1].split('/').pop();
    }

    // 4. From git remote
    if (fs.existsSync(path.join(beadsDir, '.git'))) {
      try {
        const remote = execSync('git remote get-url origin', {
          cwd: beadsDir,
          encoding: 'utf8'
        }).trim();
        // Extract repo name from URL
        const match = remote.match(/\/([^\/]+?)(\.git)?$/);
        if (match) return match[1];
      } catch (e) {}
    }

    // 5. From directory name
    return path.basename(beadsDir);
  }

  async findBeadsDir() {
    const cwd = process.cwd();

    // Check current directory
    if (fs.existsSync(`${cwd}/.beads`)) {
      return cwd;
    }

    // Check parent directories (like git)
    let dir = cwd;
    while (dir !== '/' && dir.length > 1) {
      if (fs.existsSync(`${dir}/.beads`)) {
        return dir;
      }
      dir = path.dirname(dir);
    }

    // Use default personal directory
    return path.join(os.homedir(), '.beadshub', 'personal');
  }

  async todo_list(params) {
    const { source, session, client, project } = params;

    // If filtering by session/client, query cloud
    if (session || client || (source === 'all')) {
      return await this.listFromCloud(params);
    }

    // Query local bd with label filtering
    const beadsDir = await this.findBeadsDir();
    let cmd = 'bd list --json';

    if (params.status) cmd += ` --status=${params.status}`;
    if (params.labels) {
      for (const label of params.labels) {
        cmd += ` --label="${label}"`;
      }
    }

    const result = execSync(`cd ${beadsDir} && ${cmd}`, { encoding: 'utf8' });
    const issues = JSON.parse(result);

    return {
      content: [{
        type: 'text',
        text: this.formatIssues(issues)
      }]
    };
  }

  async listFromCloud(params) {
    const queryParams = new URLSearchParams();

    if (params.source) queryParams.append('source', params.source);
    if (params.status) queryParams.append('status', params.status);
    if (params.session) queryParams.append('session', params.session);
    if (params.client) queryParams.append('client', params.client);
    if (params.project) queryParams.append('project', params.project);

    const response = await fetch(
      `https://api.beadshub.com/api/issues?${queryParams}`,
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
        text: this.formatIssues(issues)
      }]
    };
  }

  async todo_list_current_session() {
    // Convenience tool: list todos from current session
    const sessionId = await this.getSessionId();

    return await this.listFromCloud({
      session: sessionId
    });
  }

  async todo_list_by_client(params) {
    // List todos by client type
    return await this.listFromCloud({
      client: params.client
    });
  }

  async todo_ready(params) {
    if (params.source === 'all') {
      // Query cloud for ready work across all sources
      return await this.cloudAPI.getReady();
    }

    // Local ready work
    const beadsDir = await this.findBeadsDir();
    const result = execSync(`cd ${beadsDir} && bd ready --json`, { encoding: 'utf8' });
    const ready = JSON.parse(result);

    return {
      content: [{
        type: 'text',
        text: this.formatReadyWork(ready)
      }]
    };
  }

  formatIssues(issues) {
    if (issues.length === 0) {
      return 'No issues found.';
    }

    let text = `Found ${issues.length} issue(s):\n\n`;

    // Group by source if multiple sources
    const bySource = {};
    for (const issue of issues) {
      const sourceName = issue.source_name || 'unknown';
      if (!bySource[sourceName]) bySource[sourceName] = [];
      bySource[sourceName].push(issue);
    }

    for (const [source, sourceIssues] of Object.entries(bySource)) {
      if (Object.keys(bySource).length > 1) {
        text += `${source} (${sourceIssues.length}):\n`;
      }

      for (const issue of sourceIssues) {
        text += `  #${issue.id}: ${issue.title}`;
        if (issue.priority) text += ` [${issue.priority}]`;
        if (issue.blocked_by) text += ` 🔒`;

        // Show session info if available
        const sessionLabel = issue.labels?.find(l => l.startsWith('session:'));
        const clientLabel = issue.labels?.find(l => l.startsWith('client:'));

        if (sessionLabel || clientLabel) {
          text += ' (';
          if (clientLabel) text += clientLabel.split(':')[1];
          if (sessionLabel) text += ` ${sessionLabel.split(':')[1].substring(0, 8)}...`;
          text += ')';
        }

        text += '\n';
      }

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

  randomString(length) {
    return Math.random().toString(36).substring(2, 2 + length);
  }
}
```

### Cloud MCP Implementation

```typescript
// beadshub-cloud-mcp (runs on Cloudflare)

export default {
  async fetch(request: Request, env: Env) {
    // MCP server running as Cloudflare Worker

    const server = new Server({
      name: 'beadshub-cloud',
      version: '1.0.0'
    });

    server.setRequestHandler('tools/list', async () => ({
      tools: [
        {
          name: 'todo_create',
          description: 'Create todo (cloud-first)',
          inputSchema: { ... }
        },
        {
          name: 'todo_list',
          description: 'List todos from BeadsHub',
          inputSchema: { ... }
        },
        {
          name: 'todo_ready',
          description: 'Get ready work from all sources',
          inputSchema: { ... }
        }
      ]
    }));

    server.setRequestHandler('tools/call', async (req) => {
      const { name, arguments: args } = req.params;

      // All operations go through database
      switch (name) {
        case 'todo_create':
          return await createInDatabase(args, env.DB);
        case 'todo_list':
          return await listFromDatabase(args, env.DB);
        case 'todo_ready':
          return await getReadyFromDatabase(env.DB);
      }
    });

    return handleMCPRequest(request, server);
  }
};
```

**When to use which:**

- **Local MCP:** When working in coding projects, want bd features, offline
- **Cloud MCP:** When on mobile, or want cross-source queries, or no local setup

## Extending Beads

Per https://github.com/steveyegge/beads/blob/main/EXTENDING.md, we can add custom tables:

```sql
-- In .beads/beads.db

-- Beads creates these tables:
-- issues, dependencies, events, audit

-- We can add our own:
CREATE TABLE IF NOT EXISTS sync_metadata (
  issue_id TEXT PRIMARY KEY,
  cloud_id TEXT,
  synced_at INTEGER,
  cloud_updated_at INTEGER,
  FOREIGN KEY (issue_id) REFERENCES issues(id)
);

CREATE TABLE IF NOT EXISTS source_info (
  id TEXT PRIMARY KEY,
  name TEXT,
  type TEXT,
  cloud_source_id TEXT,
  last_sync INTEGER
);
```

This lets sync daemon track what's been synced without modifying Beads core.

## Web App UI

```typescript
// SvelteKit app at beadshub.com

// routes/+page.server.ts
export async function load({ locals }) {
  const user = locals.user;

  const [sources, issues, ready] = await Promise.all([
    fetchSources(user.id),
    fetchIssues(user.id),
    fetchReady(user.id)
  ]);

  return { sources, issues, ready };
}

// routes/+page.svelte
<script>
  export let data;

  let selectedSource = 'all';
  let filter = { status: 'open', labels: [] };
</script>

<div class="dashboard">
  <!-- Sidebar -->
  <aside>
    <h2>Sources ({data.sources.length})</h2>
    <ul>
      <li class:active={selectedSource === 'all'}>
        <button on:click={() => selectedSource = 'all'}>
          All Issues ({data.issues.length})
        </button>
      </li>
      {#each data.sources as source}
        <li class:active={selectedSource === source.id}>
          <button on:click={() => selectedSource = source.id}>
            {source.name} ({source.issue_count})
          </button>
        </li>
      {/each}
    </ul>
  </aside>

  <!-- Main content -->
  <main>
    <header>
      <h1>
        {selectedSource === 'all' ? 'All Issues' : data.sources.find(s => s.id === selectedSource)?.name}
      </h1>

      <div class="filters">
        <select bind:value={filter.status}>
          <option value="all">All</option>
          <option value="open">Open</option>
          <option value="closed">Closed</option>
        </select>

        <input type="search" placeholder="Search issues..." />
      </div>
    </header>

    <section class="ready-work">
      <h2>Ready to Work On ({data.ready.length})</h2>
      {#each data.ready as issue}
        <IssueCard {issue} />
      {/each}
    </section>

    <section class="all-issues">
      <h2>All Issues</h2>
      {#each filteredIssues as issue}
        <IssueRow {issue} />
      {/each}
    </section>
  </main>
</div>
```

## Mobile Apps (iOS/Android)

Native apps using same API:

```swift
// iOS app

struct IssuesView: View {
    @StateObject var viewModel = IssuesViewModel()

    var body: some View {
        NavigationView {
            List {
                Section("Ready to Work On") {
                    ForEach(viewModel.ready) { issue in
                        IssueRow(issue: issue)
                    }
                }

                Section("All Issues") {
                    ForEach(viewModel.issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }
            .navigationTitle("BeadsHub")
        }
        .task {
            await viewModel.load()
        }
    }
}

class IssuesViewModel: ObservableObject {
    @Published var issues: [Issue] = []
    @Published var ready: [Issue] = []

    func load() async {
        let response = try await URLSession.shared.data(
            from: URL(string: "https://api.beadshub.com/api/issues")!
        )
        issues = try JSONDecoder().decode([Issue].self, from: response.0)

        let readyResponse = try await URLSession.shared.data(
            from: URL(string: "https://api.beadshub.com/api/ready")!
        )
        ready = try JSONDecoder().decode([Issue].self, from: response.0)
    }
}
```

## Session Tracking & Context

Every issue automatically captures rich metadata via labels:

### Auto-Captured Labels

```javascript
// When agent creates issue
labels: [
  'session:session_1729180234_abc123',     // Current conversation
  'client:claude-code',                     // Which Claude client
  'platform:darwin',                        // OS
  'project:my-app'                          // Detected project name
]
```

### Sync Daemon Enhancement

Sync daemon extracts labels into structured fields:

```typescript
class SyncDaemon {
  async syncIssueToCloud(issue) {
    // Parse labels for metadata
    const sessionLabel = issue.labels.find(l => l.startsWith('session:'));
    const clientLabel = issue.labels.find(l => l.startsWith('client:'));
    const projectLabel = issue.labels.find(l => l.startsWith('project:'));

    // Push to cloud with extracted metadata
    await cloudAPI.upsertIssue({
      ...issue,
      session_id: sessionLabel?.split(':')[1],
      client: clientLabel?.split(':')[1],
      project_name: projectLabel?.split(':')[1]
    });
  }
}
```

### Cloud Schema Update

```sql
CREATE TABLE issues (
  -- ... existing fields ...

  -- Session tracking
  session_id TEXT,
  client TEXT,            -- 'claude-code', 'claude-desktop', 'claude-mobile'
  project_name TEXT,

  -- Indexes for filtering
  CREATE INDEX idx_issues_session ON issues(session_id);
  CREATE INDEX idx_issues_client ON issues(client);
  CREATE INDEX idx_issues_project ON issues(project_name);
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  client TEXT NOT NULL,
  project_name TEXT,
  first_issue INTEGER,
  last_issue INTEGER,
  issue_count INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
```

### Query Examples

**Example 1: Show me todos from this Claude session**

```bash
User: "Show me todos from this conversation"

# MCP server
Claude → todo_list({ session: getCurrentSessionId() })

# Cloud API
GET /api/issues?session=session_1729180234_abc123

# Response: Only issues created in this session
```

**Example 2: What did I do in Claude Code today?**

```bash
User: "What todos did I create in Claude Code today?"

Claude → todo_list({
  client: 'claude-code',
  created_after: startOfToday()
})

# Response: All Claude Code issues from today
```

**Example 3: Show all project-a issues**

```bash
User: "Show me all issues for project-a"

Claude → todo_list({ project: 'project-a' })

# Response: All issues labeled with project:project-a
```

**Example 4: Cross-session view**

```bash
User: "Show me all my auth-related todos across all sessions"

Claude → todo_list({ labels: ['auth'] })

# Response: All auth issues from:
# - Claude Code session from yesterday
# - Claude Desktop session from today
# - Claude Mobile session from last week
```

### BeadsHub UI

```
beadshub.com/issues

Filters:
☑ Show all sources
☐ Filter by:
  Session: [Current session ▼]
  Client: [All ▼]
  Project: [All ▼]

----------------------------------------

Claude Code - Today 2:30 PM (Session abc123)
  #54 Fix login bug (project-a)
  #55 Add rate limiting (project-a)

Claude Desktop - Yesterday 4:15 PM (Session def456)
  #52 Review PR (side-project)
  #53 Update docs (side-project)

Claude Mobile - Oct 15 (Session ghi789)
  #48 Call John
  #49 Review mockups
```

Click session → see all issues from that conversation.

### Mobile App Context

When viewing on iOS:

```swift
struct SessionsView: View {
    @StateObject var viewModel = SessionsViewModel()

    var body: some View {
        List {
            Section("Recent Sessions") {
                ForEach(viewModel.sessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session)) {
                        VStack(alignment: .leading) {
                            Text(session.clientName)
                                .font(.headline)
                            Text("\(session.issueCount) issues")
                                .font(.caption)
                            Text(session.lastActive.formatted())
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }
}

// API call
GET /api/sessions?user_id=xxx

Response:
[
  {
    "id": "session_abc123",
    "client": "claude-code",
    "project": "project-a",
    "issue_count": 5,
    "last_active": 1729180234
  },
  {
    "id": "session_def456",
    "client": "claude-desktop",
    "project": "side-project",
    "issue_count": 2,
    "last_active": 1729094000
  }
]
```

### Conversation Title (Future Enhancement)

**Problem:** MCP can't access conversation titles from Claude.

**Solution:** Let user name sessions in BeadsHub:

```
beadshub.com/sessions/session_abc123

Session abc123
Client: Claude Code
Project: project-a
Started: Oct 17, 2:30 PM
Issues: 5

[Name this session]  →  "Implementing Auth System"

---

After naming:

Session: "Implementing Auth System"
Client: Claude Code
Project: project-a
5 issues

#54 Fix login bug
#55 Add rate limiting
...
```

Or prompt first time:

```
User creates 3rd issue in session

Claude: "You've created 3 issues in this session. Want to name it?"

User: "Auth system work"

Claude: "✓ Named this session: Auth system work"
```

## Summary

**BeadsHub is GitHub for bd:**

1. **Local:** Use `bd` CLI exactly as designed (no changes needed)
2. **Sync Daemon:** Auto-discovers ALL `.beads/` directories, syncs to cloud
3. **Cloud:** Cloudflare Workers + D1 to aggregate everything
4. **UIs:** Web + iOS + macOS apps to view/manage
5. **MCP:** Both local (wraps bd) and cloud (direct API access)
6. **Session Tracking:** Auto-captures which Claude session/client created each issue

**For your 30+ projects:**
- Each has `.beads/` directory
- Sync daemon finds them all automatically
- See everything in one place on beadshub.com
- Filter by source, or view all

**For random sessions:**
- Default personal `.beads/` directory
- Or session-based sources
- Or just use labels, don't worry about sources

**For context tracking:**
- Every issue tagged with session ID, client, project
- Query: "Show todos from this conversation"
- Query: "What did I do in Claude Code today?"
- Query: "Show all auth issues across all sessions"

**Key insight:** You don't have to organize anything. BeadsHub finds all `.beads/` directories and aggregates them. Session tracking is automatic. Just like GitHub finds all your repos.

Want me to design the sync protocol details and conflict resolution?
