# beadster PoC Plan

## Goal

Create minimal working system where:
1. Agent creates todo via MCP
2. Todo synced to cloud
3. Visible on web UI

**Skip:** macOS/iOS apps for now
**Use:** CLI tools + MCP + web UI

## Architecture

```
Claude Code (MCP)
    ↓
Local .beads/ (bd CLI)
    ↓
Sync daemon (Node.js script)
    ↓
Cloud API (Cloudflare Workers + D1)
    ↓
Web UI (simple HTML or Astro)
```

## Components to Build

### 1. Cloud Backend (Cloudflare)

**Stack:** Cloudflare Workers + D1 + Hono

**What to build:**

```
beadster-api/
├── src/
│   ├── index.ts           # Main worker
│   ├── db/
│   │   ├── schema.sql     # D1 schema
│   │   └── queries.ts     # Database queries
│   ├── routes/
│   │   ├── auth.ts        # Simple API key auth
│   │   ├── sources.ts     # Sources endpoints
│   │   └── issues.ts      # Issues endpoints
│   └── types.ts           # TypeScript types
├── wrangler.jsonc         # Cloudflare config
└── package.json
```

**Minimal schema:**

```sql
-- schema.sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE,
  api_key TEXT UNIQUE NOT NULL,
  created_at INTEGER
);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT,  -- 'local', 'virtual', 'inbox'
  path TEXT,
  last_sync INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,

  -- From Beads
  beads_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  status TEXT NOT NULL,
  priority TEXT,
  labels TEXT,  -- JSON array

  -- Session tracking (extracted from labels)
  session_id TEXT,
  client TEXT,  -- 'claude-code', 'claude-desktop', etc
  project_name TEXT,

  -- Sync
  synced_at INTEGER,

  -- Timestamps
  created_at INTEGER,
  updated_at INTEGER,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id)
);

CREATE INDEX idx_issues_user ON issues(user_id);
CREATE INDEX idx_issues_source ON issues(source_id);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_session ON issues(session_id);
CREATE INDEX idx_issues_client ON issues(client);

-- Sessions for grouping
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT,
  client TEXT NOT NULL,
  project_name TEXT,
  first_issue_at INTEGER,
  last_issue_at INTEGER,
  issue_count INTEGER DEFAULT 0,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id)
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_source ON sessions(source_id);
```

**Minimal API endpoints:**

```typescript
// src/index.ts
import { Hono } from 'hono';
import { cors } from 'hono/cors';

const app = new Hono();

app.use('/*', cors());

// Health check
app.get('/', (c) => c.json({ status: 'ok' }));

// Auth: Create API key (for PoC, just generate)
app.post('/api/auth/register', async (c) => {
  const { email } = await c.req.json();

  const userId = crypto.randomUUID();
  const apiKey = crypto.randomUUID();

  await c.env.DB.prepare(`
    INSERT INTO users (id, email, api_key, created_at)
    VALUES (?, ?, ?, ?)
  `).bind(userId, email, apiKey, Date.now()).run();

  return c.json({ user_id: userId, api_key: apiKey });
});

// Sync: Push issues from daemon
app.post('/api/sync/push', async (c) => {
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '');
  const user = await authenticate(c.env.DB, apiKey);

  const { source, issues } = await c.req.json();

  // Upsert source
  await c.env.DB.prepare(`
    INSERT INTO sources (id, user_id, name, type, path, last_sync)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET last_sync = ?
  `).bind(
    source.id,
    user.id,
    source.name,
    source.type,
    source.path,
    Date.now(),
    Date.now()
  ).run();

  // Upsert issues
  for (const issue of issues) {
    await c.env.DB.prepare(`
      INSERT INTO issues (
        id, user_id, source_id, beads_id, title, body,
        status, priority, labels, synced_at, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        body = excluded.body,
        status = excluded.status,
        priority = excluded.priority,
        labels = excluded.labels,
        synced_at = excluded.synced_at,
        updated_at = excluded.updated_at
    `).bind(
      issue.id,
      user.id,
      source.id,
      issue.beads_id,
      issue.title,
      issue.body,
      issue.status,
      issue.priority,
      JSON.stringify(issue.labels),
      Date.now(),
      issue.created_at,
      issue.updated_at
    ).run();
  }

  return c.json({ synced: issues.length });
});

// Sync: Pull changes from cloud
app.get('/api/sync/pull', async (c) => {
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '');
  const user = await authenticate(c.env.DB, apiKey);

  const sourceId = c.req.query('source_id');
  const since = parseInt(c.req.query('since') || '0');

  const changes = await c.env.DB.prepare(`
    SELECT * FROM issues
    WHERE source_id = ? AND user_id = ? AND updated_at > ?
  `).bind(sourceId, user.id, since).all();

  return c.json(changes.results);
});

// Web: List issues for user
app.get('/api/issues', async (c) => {
  const apiKey = c.req.query('api_key');
  const user = await authenticate(c.env.DB, apiKey);

  const issues = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ?
    ORDER BY i.created_at DESC
  `).bind(user.id).all();

  return c.json(issues.results);
});

async function authenticate(db: D1Database, apiKey: string) {
  const user = await db.prepare(`
    SELECT * FROM users WHERE api_key = ?
  `).bind(apiKey).first();

  if (!user) {
    throw new Error('Unauthorized');
  }

  return user;
}

export default app;
```

**Deploy:**

```bash
cd beadster-api
npm install hono
npx wrangler d1 create beadster-db
npx wrangler d1 execute beadster-db --file=src/db/schema.sql
npx wrangler deploy
```

### 2. Sync Daemon (Swift)

**Swift CLI tool that watches .beads/ and syncs bidirectionally**

**Why Swift?**
- ✅ Same code will be used in macOS app
- ✅ Native file watching (FSEvents)
- ✅ SQLite is built-in
- ✅ Can compile to standalone binary

```
beadster-sync/
├── Sources/
│   └── beadsterSync/
│       ├── main.swift           # Entry point
│       ├── SyncDaemon.swift     # Main daemon
│       ├── FileWatcher.swift    # FSEvents watcher
│       ├── BeadsDatabase.swift  # SQLite reader/writer
│       ├── CloudAPI.swift       # API client
│       └── Models.swift         # Data models
├── Package.swift
└── README.md
```

**Implementation:**

```swift
// Models.swift
struct Config: Codable {
    let apiKey: String
    let apiUrl: String
    let sources: [Source]
}

struct Source: Codable {
    let name: String
    let path: String
}

struct Issue: Codable {
    let id: String
    let beadsId: String
    let title: String
    let body: String?
    let status: String
    let priority: String?
    let labels: [String]
    let createdAt: Int
    let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id, title, body, status, priority, labels
        case beadsId = "beads_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// BeadsDatabase.swift
import SQLite3
import Foundation

class BeadsDatabase {
    private let dbPath: String
    private var db: OpaquePointer?

    init(beadsDir: String) {
        self.dbPath = "\(beadsDir)/.beads/beads.db"
    }

    func open() throws {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }
    }

    func close() {
        sqlite3_close(db)
    }

    func getAllIssues() throws -> [Issue] {
        var issues: [Issue] = []

        let query = """
        SELECT id, title, body, status, priority, labels, created_at, updated_at
        FROM issues
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let body = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let status = String(cString: sqlite3_column_text(statement, 3))
            let priority = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            let labelsJSON = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "[]"
            let createdAt = Int(sqlite3_column_int64(statement, 6))
            let updatedAt = Int(sqlite3_column_int64(statement, 7))

            let labels = try? JSONDecoder().decode([String].self, from: labelsJSON.data(using: .utf8)!) ?? []

            issues.append(Issue(
                id: id,
                beadsId: id,
                title: title,
                body: body,
                status: status,
                priority: priority,
                labels: labels ?? [],
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }

        return issues
    }

    // For pulling changes from cloud
    func updateIssue(_ issue: Issue) throws {
        let query = """
        UPDATE issues
        SET title = ?, body = ?, status = ?, priority = ?, updated_at = ?
        WHERE id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (issue.title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (issue.body as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (issue.status as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (issue.priority as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_int64(statement, 5, Int64(issue.updatedAt))
        sqlite3_bind_text(statement, 6, (issue.beadsId as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.updateFailed
        }
    }
}

enum DatabaseError: Error {
    case cantOpen
    case queryFailed
    case updateFailed
}

// CloudAPI.swift
import Foundation

class CloudAPI {
    private let apiUrl: String
    private let apiKey: String

    init(apiUrl: String, apiKey: String) {
        self.apiUrl = apiUrl
        self.apiKey = apiKey
    }

    func pushIssues(source: Source, issues: [Issue]) async throws {
        let sourceId = generateSourceId(path: source.path)

        let payload: [String: Any] = [
            "source": [
                "id": sourceId,
                "name": source.name,
                "type": "local",
                "path": source.path
            ],
            "issues": issues.map { issue in
                [
                    "id": "\(sourceId)_\(issue.beadsId)",
                    "beads_id": issue.beadsId,
                    "title": issue.title,
                    "body": issue.body as Any,
                    "status": issue.status,
                    "priority": issue.priority as Any,
                    "labels": issue.labels,
                    "created_at": issue.createdAt,
                    "updated_at": issue.updatedAt
                ]
            }
        ]

        let url = URL(string: "\(apiUrl)/api/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.pushFailed
        }
    }

    func pullChanges(source: Source, since: Int) async throws -> [Issue] {
        let sourceId = generateSourceId(path: source.path)
        let url = URL(string: "\(apiUrl)/api/sync/pull?source_id=\(sourceId)&since=\(since)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.pullFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let changes = try decoder.decode([Issue].self, from: data)

        return changes
    }

    private func generateSourceId(path: String) -> String {
        return path.data(using: .utf8)!.base64EncodedString()
            .prefix(16)
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

enum APIError: Error {
    case pushFailed
    case pullFailed
}

// FileWatcher.swift
import Foundation

class FileWatcher {
    private let path: String
    private let callback: () -> Void
    private var streamRef: FSEventStreamRef?

    init(path: String, callback: @escaping () -> Void) {
        self.path = path
        self.callback = callback
    }

    func start() {
        let pathsToWatch = ["\(path)/.beads/issues"] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, eventIds in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.callback()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents)
        )

        guard let streamRef = streamRef else { return }

        FSEventStreamScheduleWithRunLoop(streamRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(streamRef)
    }

    func stop() {
        guard let streamRef = streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
    }
}

// SyncDaemon.swift
import Foundation

class SyncDaemon {
    private let config: Config
    private var watchers: [FileWatcher] = []
    private var lastSync: [String: Int] = [:] // source path -> timestamp

    init(configPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        self.config = try JSONDecoder().decode(Config.self, from: data)
    }

    func start() async {
        print("beadster sync daemon starting...")

        // Initial sync
        for source in config.sources {
            await syncSource(source)
        }

        // Watch for changes
        for source in config.sources {
            watchSource(source)
        }

        print("Watching \(config.sources.count) sources")

        // Pull changes every 10 seconds
        Task {
            while true {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                for source in config.sources {
                    await pullChanges(source)
                }
            }
        }

        // Keep running
        RunLoop.main.run()
    }

    func syncSource(_ source: Source) async {
        do {
            let db = BeadsDatabase(beadsDir: source.path)
            try db.open()
            defer { db.close() }

            let issues = try db.getAllIssues()

            let api = CloudAPI(apiUrl: config.apiUrl, apiKey: config.apiKey)
            try await api.pushIssues(source: source, issues: issues)

            lastSync[source.path] = Int(Date().timeIntervalSince1970)

            print("✓ Synced \(issues.count) issues from \(source.name)")
        } catch {
            print("✗ Sync failed for \(source.name): \(error)")
        }
    }

    func pullChanges(_ source: Source) async {
        do {
            let since = lastSync[source.path] ?? 0

            let api = CloudAPI(apiUrl: config.apiUrl, apiKey: config.apiKey)
            let changes = try await api.pullChanges(source: source, since: since)

            if !changes.isEmpty {
                print("⬇ Pulling \(changes.count) changes for \(source.name)")

                // Apply changes via bd CLI
                for issue in changes {
                    try applyChange(source: source, issue: issue)
                }

                lastSync[source.path] = Int(Date().timeIntervalSince1970)
            }
        } catch {
            print("✗ Pull failed for \(source.name): \(error)")
        }
    }

    func applyChange(source: Source, issue: Issue) throws {
        // Use bd CLI to update issue (lets Beads handle JSONL + DB consistency)
        let command = """
        cd \(source.path) && bd update \(issue.beadsId) \
        --title="\(issue.title)" \
        --status=\(issue.status)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        try process.run()
        process.waitUntilExit()
    }

    func watchSource(_ source: Source) {
        let watcher = FileWatcher(path: source.path) { [weak self] in
            guard let self = self else { return }
            Task {
                await self.syncSource(source)
            }
        }
        watcher.start()
        watchers.append(watcher)
    }
}

// main.swift
import Foundation

let configPath = "\(NSHomeDirectory())/.beadster/config.json"

guard FileManager.default.fileExists(atPath: configPath) else {
    print("Error: Config file not found at \(configPath)")
    print("Create ~/.beadster/config.json with your API key and sources")
    exit(1)
}

do {
    let daemon = try SyncDaemon(configPath: configPath)
    await daemon.start()
} catch {
    print("Error: \(error)")
    exit(1)
}
```

**Package.swift:**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "beadsterSync",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "beadsterSync",
            dependencies: [],
            path: "Sources/beadsterSync"
        )
    ]
)
```

**Config file:**

```json
// ~/.beadster/config.json
{
  "apiKey": "your-api-key",
  "apiUrl": "https://api.beadster.com",
  "sources": [
    {
      "name": "main-app",
      "path": "/Users/anton/projects/main-app"
    },
    {
      "name": "side-project",
      "path": "/Users/anton/projects/side-project"
    }
  ]
}
```

**Install & run:**

```bash
cd beadster-sync
npm install
npm run build
npm start
# Or: npm run dev (with watch mode)
```

### 3. MCP Server (Minimal)

**Just wrap bd CLI for now**

```
beadster-mcp/
├── src/
│   └── index.ts
├── package.json
└── build.json
```

**Implementation:**

```typescript
// src/index.ts
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

const server = new Server(
  {
    name: 'beadster-mcp',
    version: '0.1.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler('tools/list', async () => ({
  tools: [
    {
      name: 'todo_create',
      description: 'Create a todo using Beads',
      inputSchema: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'Todo title' },
          body: { type: 'string', description: 'Todo description' },
          priority: { type: 'string', enum: ['low', 'normal', 'high'] },
          labels: { type: 'array', items: { type: 'string' } }
        },
        required: ['title']
      }
    },
    {
      name: 'todo_list',
      description: 'List todos',
      inputSchema: {
        type: 'object',
        properties: {
          status: { type: 'string', enum: ['open', 'closed', 'all'] }
        }
      }
    },
    {
      name: 'todo_complete',
      description: 'Mark todo as complete',
      inputSchema: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'Issue ID' }
        },
        required: ['id']
      }
    }
  ]
}));

server.setRequestHandler('tools/call', async (request) => {
  const { name, arguments: args } = request.params;

  const beadsDir = findBeadsDir();

  switch (name) {
    case 'todo_create': {
      let cmd = `cd ${beadsDir} && bd create "${args.title}"`;
      if (args.body) cmd += ` --body="${args.body}"`;
      if (args.priority) cmd += ` --priority=${args.priority}`;
      if (args.labels) {
        for (const label of args.labels) {
          cmd += ` --label="${label}"`;
        }
      }
      cmd += ' --json';

      const output = execSync(cmd, { encoding: 'utf8' });
      const issue = JSON.parse(output);

      return {
        content: [{
          type: 'text',
          text: `✓ Created todo #${issue.id}: ${args.title}`
        }]
      };
    }

    case 'todo_list': {
      let cmd = `cd ${beadsDir} && bd list --json`;
      if (args.status && args.status !== 'all') {
        cmd += ` --status=${args.status}`;
      }

      const output = execSync(cmd, { encoding: 'utf8' });
      const issues = JSON.parse(output);

      let text = `Found ${issues.length} todos:\n\n`;
      for (const issue of issues) {
        text += `#${issue.id}: ${issue.title} [${issue.status}]\n`;
      }

      return {
        content: [{ type: 'text', text }]
      };
    }

    case 'todo_complete': {
      const cmd = `cd ${beadsDir} && bd close ${args.id}`;
      execSync(cmd);

      return {
        content: [{
          type: 'text',
          text: `✓ Marked todo #${args.id} as complete`
        }]
      };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

function findBeadsDir(): string {
  let dir = process.cwd();

  while (dir !== '/' && dir.length > 1) {
    if (fs.existsSync(path.join(dir, '.beads'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }

  // Use inbox as fallback
  const inbox = path.join(process.env.HOME!, '.beadster', 'inbox');
  if (!fs.existsSync(path.join(inbox, '.beads'))) {
    fs.mkdirSync(inbox, { recursive: true });
    execSync(`cd ${inbox} && bd init`);
  }

  return inbox;
}

const transport = new StdioServerTransport();
server.connect(transport);
```

**Configure in Claude Code:**

```json
// ~/.claude/mcp.json
{
  "mcpServers": {
    "beadster": {
      "command": "node",
      "args": ["/path/to/beadster-mcp/dist/index.js"]
    }
  }
}
```

### 4. Web UI (Simple HTML)

**Ultra-minimal web interface**

```
beadster-web/
├── src/
│   └── pages/
│       └── index.astro
├── astro.config.mjs
└── package.json
```

**Implementation:**

```astro
---
// src/pages/index.astro
const apiKey = Astro.url.searchParams.get('api_key');

let issues = [];
if (apiKey) {
  const response = await fetch(
    `https://api.beadster.com/api/issues?api_key=${apiKey}`
  );
  issues = await response.json();
}
---

<html>
<head>
  <title>beadster</title>
  <style>
    body {
      font-family: system-ui;
      max-width: 800px;
      margin: 40px auto;
      padding: 0 20px;
    }
    .issue {
      border: 1px solid #ddd;
      padding: 15px;
      margin: 10px 0;
      border-radius: 8px;
    }
    .issue-title {
      font-weight: bold;
      font-size: 16px;
    }
    .issue-meta {
      color: #666;
      font-size: 12px;
      margin-top: 5px;
    }
    .status-open { color: green; }
    .status-closed { color: gray; }
    input { padding: 8px; width: 300px; }
    button { padding: 8px 16px; }
  </style>
</head>
<body>
  <h1>beadster</h1>

  {!apiKey ? (
    <form>
      <input type="text" name="api_key" placeholder="Enter your API key" />
      <button>View Issues</button>
    </form>
  ) : (
    <>
      <p>Viewing {issues.length} issues</p>

      {issues.map(issue => (
        <div class="issue">
          <div class="issue-title">{issue.title}</div>
          <div class="issue-meta">
            <span class={`status-${issue.status}`}>{issue.status}</span>
            {' • '}
            {issue.source_name}
            {issue.priority && ` • ${issue.priority} priority`}
          </div>
          {issue.body && <p>{issue.body}</p>}
        </div>
      ))}
    </>
  )}
</body>
</html>
```

**Deploy to Cloudflare Pages:**

```bash
cd beadster-web
npm create astro@latest
npm install
npm run build
npx wrangler pages deploy dist
```

## Setup Steps

### 1. Install Beads

```bash
# Install bd CLI
git clone https://github.com/steveyegge/beads
cd beads
go build
cp bd /usr/local/bin/

# Test it
cd ~/projects/test-project
bd init
bd create "Test issue"
bd list
```

### 2. Deploy Cloud API

```bash
# Create project
mkdir beadster-api
cd beadster-api

# Install dependencies
npm init -y
npm install hono
npm install -D @cloudflare/workers-types wrangler

# Create files (use code above)
# ... create src/index.ts, schema.sql, wrangler.jsonc

# Create D1 database
npx wrangler d1 create beadster-db

# Run migrations
npx wrangler d1 execute beadster-db --file=src/db/schema.sql

# Deploy
npx wrangler deploy
```

### 3. Register User & Get API Key

```bash
curl -X POST https://api.beadster.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com"}'

# Returns: {"user_id":"...", "api_key":"..."}
```

### 4. Setup Sync Daemon

```bash
# Create project
mkdir beadster-sync
cd beadster-sync

npm init -y
npm install better-sqlite3 chokidar
npm install -D @types/better-sqlite3 @types/node typescript

# Create files (use code above)
# ... create src/index.ts

# Create config
mkdir -p ~/.beadster
cat > ~/.beadster/config.json << EOF
{
  "apiKey": "YOUR_API_KEY",
  "apiUrl": "https://api.beadster.com",
  "sources": [
    {
      "name": "test-project",
      "path": "$HOME/projects/test-project"
    }
  ]
}
EOF

# Build and run
npm run build
npm start
```

### 5. Setup MCP Server

```bash
# Create project
mkdir beadster-mcp
cd beadster-mcp

npm init -y
npm install @modelcontextprotocol/sdk
npm install -D typescript @types/node

# Create files (use code above)
# ... create src/index.ts

# Build
npm run build

# Configure in Claude Code
cat > ~/.claude/mcp.json << EOF
{
  "mcpServers": {
    "beadster": {
      "command": "node",
      "args": ["$PWD/dist/index.js"]
    }
  }
}
EOF
```

### 6. Deploy Web UI

```bash
# Create Astro project
npm create astro@latest beadster-web
cd beadster-web

# Create page (use code above)
# ... create src/pages/index.astro

# Build
npm run build

# Deploy
npx wrangler pages deploy dist
```

## Testing the PoC

### 1. Create issue via Claude Code

```
User: "Create todo: Implement OAuth"

Claude (via MCP):
→ Calls bd create in ~/projects/test-project
→ Issue created in .beads/
```

### 2. Sync daemon picks it up

```
Sync daemon watching ~/projects/test-project
→ Detects new issue file
→ Reads from beads.db
→ Pushes to cloud API
✓ Synced 1 issue
```

### 3. View on web

```
Open https://beadster.pages.dev?api_key=YOUR_KEY

→ Shows: "Implement OAuth" (open)
```

## What's NOT in PoC

- ❌ Mac/iOS apps
- ❌ Apple ID auth (just API keys)
- ❌ Sharing
- ❌ Claude log context
- ❌ Security-scoped bookmarks
- ❌ Bidirectional sync (cloud → local)
- ❌ Conflict resolution
- ❌ Real-time updates
- ❌ Session tracking

## What IS in PoC

- ✅ bd CLI for issue management
- ✅ MCP server for Claude Code
- ✅ Sync daemon (local → cloud)
- ✅ Cloud API (Cloudflare Workers + D1)
- ✅ Web UI to view issues
- ✅ API key authentication
- ✅ Multi-source support

## Time Estimate

- Cloud API: 2-3 hours
- Sync daemon: 2-3 hours
- MCP server: 1-2 hours
- Web UI: 1 hour
- Setup & testing: 1-2 hours

**Total: 7-11 hours** (1-2 days)

## Success Criteria

✅ Agent creates todo in Claude Code
✅ Todo appears in .beads/ directory
✅ Sync daemon pushes to cloud
✅ Web UI shows the todo
✅ Works with multiple projects

When this works, we have proven the core concept!
