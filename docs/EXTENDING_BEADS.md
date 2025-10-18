# How beadster Extends Beads

## Philosophy

**Beads is perfect as-is. Don't modify it.**

Following the EXTENDING.md guidelines, beadster adds orchestration layers WITHOUT touching Beads core.

## What Beads Provides

```
.beads/
├── issues/              # JSONL files (Beads manages)
├── beads.db             # SQLite database (Beads rebuilds)
└── config.toml          # Beads config
```

**Beads tables:**
- `issues` - Core issue tracking
- `dependencies` - Blocks, parent-child relationships
- `events` - Issue history
- `audit` - Change tracking

## What beadster Adds

### 1. Custom Tables in Same Database

Following EXTENDING.md pattern, add namespaced tables:

```sql
-- In .beads/beads.db

-- beadster sync metadata
CREATE TABLE IF NOT EXISTS beadster_sync (
  issue_id TEXT PRIMARY KEY,
  cloud_id TEXT,
  synced_at INTEGER,
  cloud_updated_at INTEGER,
  sync_status TEXT,  -- 'synced', 'pending', 'conflict'
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_beadster_sync_status ON beadster_sync(sync_status);
CREATE INDEX idx_beadster_sync_cloud_id ON beadster_sync(cloud_id);

-- beadster source info
CREATE TABLE IF NOT EXISTS beadster_source (
  id TEXT PRIMARY KEY DEFAULT 1,  -- Only one row
  name TEXT,
  cloud_source_id TEXT,
  last_sync INTEGER,
  sync_enabled INTEGER DEFAULT 1,
  tags TEXT,  -- JSON array
  -- For sandboxed apps: security-scoped bookmark
  bookmark TEXT,  -- Base64-encoded bookmark data
  bookmark_updated_at INTEGER
);

-- beadster session tracking (from labels)
CREATE TABLE IF NOT EXISTS beadster_sessions (
  session_id TEXT PRIMARY KEY,
  first_issue_id TEXT,
  last_issue_id TEXT,
  first_seen INTEGER,
  last_seen INTEGER,
  client TEXT,
  project TEXT,
  issue_count INTEGER
);

CREATE INDEX idx_beadster_sessions_client ON beadster_sessions(client);
CREATE INDEX idx_beadster_sessions_project ON beadster_sessions(project);

-- beadster conflict resolution
CREATE TABLE IF NOT EXISTS beadster_conflicts (
  id TEXT PRIMARY KEY,
  issue_id TEXT,
  conflict_type TEXT,  -- 'update_conflict', 'delete_conflict'
  local_state TEXT,    -- JSON
  cloud_state TEXT,    -- JSON
  detected_at INTEGER,
  resolved INTEGER DEFAULT 0,
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);
```

### 2. Access Pattern

**Sync daemon reads Beads data, adds beadster metadata:**

```typescript
class SyncDaemon {
  async syncIssue(issueId: string) {
    const db = new Database(`${beadsDir}/beads.db`);

    // 1. Read from Beads tables (read-only)
    const issue = db.prepare(`
      SELECT * FROM issues WHERE id = ?
    `).get(issueId);

    // 2. Check beadster sync status
    const syncStatus = db.prepare(`
      SELECT * FROM beadster_sync WHERE issue_id = ?
    `).get(issueId);

    if (syncStatus && syncStatus.synced_at > issue.updated_at) {
      // Already synced
      return;
    }

    // 3. Push to cloud
    const cloudIssue = await this.pushToCloud(issue);

    // 4. Update beadster metadata (write to our tables only)
    db.prepare(`
      INSERT INTO beadster_sync (issue_id, cloud_id, synced_at, sync_status)
      VALUES (?, ?, ?, 'synced')
      ON CONFLICT(issue_id) DO UPDATE SET
        synced_at = excluded.synced_at,
        cloud_id = excluded.cloud_id,
        sync_status = 'synced'
    `).run(issueId, cloudIssue.id, Date.now());
  }

  async pullCloudChanges() {
    const changes = await this.fetchCloudChanges();

    for (const change of changes) {
      // Use bd CLI to update issue (let Beads handle it)
      execSync(`bd update ${change.id} --title="${change.title}"`);

      // Update our sync metadata
      db.prepare(`
        UPDATE beadster_sync
        SET cloud_updated_at = ?, sync_status = 'synced'
        WHERE issue_id = ?
      `).run(Date.now(), change.id);
    }
  }
}
```

### 3. Session Tracking via Labels

**We don't modify Beads schema. Use labels:**

```typescript
// When creating issue via MCP
class beadsterMCP {
  async todo_create(params) {
    const beadsDir = await this.findBeadsDir();

    // Build labels with session metadata
    const labels = [
      ...(params.labels || []),
      `session:${await this.getSessionId()}`,
      `client:${await this.getClientType()}`,
      `project:${await this.getProjectName()}`
    ];

    // Create via bd CLI (Beads handles everything)
    let cmd = `bd create "${params.title}"`;
    for (const label of labels) {
      cmd += ` --label="${label}"`;
    }

    execSync(`cd ${beadsDir} && ${cmd}`);

    // Extract session info and update our tracking table
    await this.updateSessionTracking(labels);
  }

  async updateSessionTracking(labels: string[]) {
    const sessionLabel = labels.find(l => l.startsWith('session:'));
    const clientLabel = labels.find(l => l.startsWith('client:'));
    const projectLabel = labels.find(l => l.startsWith('project:'));

    if (!sessionLabel) return;

    const sessionId = sessionLabel.split(':')[1];
    const client = clientLabel?.split(':')[1];
    const project = projectLabel?.split(':')[1];

    const db = new Database(`${beadsDir}/beads.db`);

    db.prepare(`
      INSERT INTO beadster_sessions (
        session_id, first_seen, last_seen, client, project, issue_count
      )
      VALUES (?, ?, ?, ?, ?, 1)
      ON CONFLICT(session_id) DO UPDATE SET
        last_seen = excluded.last_seen,
        issue_count = issue_count + 1
    `).run(sessionId, Date.now(), Date.now(), client, project);
  }
}
```

### 4. Query Both Beads and beadster Data

```typescript
// Query issues with session info
async function getIssuesWithSessions(sourceId: string) {
  const db = new Database(`${beadsDir}/beads.db`);

  const issues = db.prepare(`
    SELECT
      i.*,
      s.synced_at,
      s.cloud_id,
      s.sync_status
    FROM issues i
    LEFT JOIN beadster_sync s ON s.issue_id = i.id
    WHERE i.status = 'open'
    ORDER BY i.created_at DESC
  `).all();

  return issues;
}

// Query by session
async function getIssuesBySession(sessionId: string) {
  const db = new Database(`${beadsDir}/beads.db`);

  // Query issues by label (Beads native)
  const issues = db.prepare(`
    SELECT i.*
    FROM issues i
    WHERE i.labels LIKE ?
  `).all(`%session:${sessionId}%`);

  return issues;
}

// Query session stats
async function getSessionStats() {
  const db = new Database(`${beadsDir}/beads.db`);

  const sessions = db.prepare(`
    SELECT
      session_id,
      client,
      project,
      issue_count,
      first_seen,
      last_seen
    FROM beadster_sessions
    ORDER BY last_seen DESC
    LIMIT 20
  `).all();

  return sessions;
}
```

### 5. Database Initialization

**On first use, create beadster tables:**

```typescript
class beadsterExtension {
  async initialize(beadsDir: string) {
    const dbPath = path.join(beadsDir, '.beads', 'beads.db');

    if (!fs.existsSync(dbPath)) {
      throw new Error('Beads database not found. Run `bd init` first.');
    }

    const db = new Database(dbPath);

    // Create beadster extension tables
    db.exec(`
      CREATE TABLE IF NOT EXISTS beadster_sync (
        issue_id TEXT PRIMARY KEY,
        cloud_id TEXT,
        synced_at INTEGER,
        cloud_updated_at INTEGER,
        sync_status TEXT,
        FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_beadster_sync_status
        ON beadster_sync(sync_status);

      CREATE TABLE IF NOT EXISTS beadster_source (
        id TEXT PRIMARY KEY DEFAULT 1,
        name TEXT,
        cloud_source_id TEXT,
        last_sync INTEGER,
        sync_enabled INTEGER DEFAULT 1,
        tags TEXT
      );

      CREATE TABLE IF NOT EXISTS beadster_sessions (
        session_id TEXT PRIMARY KEY,
        first_issue_id TEXT,
        last_issue_id TEXT,
        first_seen INTEGER,
        last_seen INTEGER,
        client TEXT,
        project TEXT,
        issue_count INTEGER
      );

      CREATE TABLE IF NOT EXISTS beadster_conflicts (
        id TEXT PRIMARY KEY,
        issue_id TEXT,
        conflict_type TEXT,
        local_state TEXT,
        cloud_state TEXT,
        detected_at INTEGER,
        resolved INTEGER DEFAULT 0,
        FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
      );

      -- Store extension version
      CREATE TABLE IF NOT EXISTS beadster_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      );

      INSERT OR REPLACE INTO beadster_meta (key, value)
      VALUES ('version', '1.0.0');
    `);

    db.close();
  }
}
```

### 6. Conflict Resolution

**When cloud and local diverge:**

```typescript
async function handleConflict(issueId: string) {
  const db = new Database(`${beadsDir}/beads.db`);

  // Get local state from Beads
  const localIssue = db.prepare(`
    SELECT * FROM issues WHERE id = ?
  `).get(issueId);

  // Get cloud state
  const cloudIssue = await api.getIssue(cloudId);

  // Check sync metadata
  const syncInfo = db.prepare(`
    SELECT * FROM beadster_sync WHERE issue_id = ?
  `).get(issueId);

  if (localIssue.updated_at > syncInfo.synced_at &&
      cloudIssue.updated_at > syncInfo.cloud_updated_at) {
    // Both changed - conflict!

    // Store conflict for user resolution
    db.prepare(`
      INSERT INTO beadster_conflicts (
        id, issue_id, conflict_type, local_state, cloud_state, detected_at
      )
      VALUES (?, ?, 'update_conflict', ?, ?, ?)
    `).run(
      `conflict_${Date.now()}`,
      issueId,
      JSON.stringify(localIssue),
      JSON.stringify(cloudIssue),
      Date.now()
    );

    // Notify user
    this.notifyConflict(issueId);
  }
}
```

### 7. JSON for Flexible Metadata

**Store complex state using SQLite JSON:**

```sql
-- beadster cache (for quick queries)
CREATE TABLE IF NOT EXISTS beadster_cache (
  key TEXT PRIMARY KEY,
  value TEXT,  -- JSON
  expires_at INTEGER
);

-- Example: Cache ready work
INSERT INTO beadster_cache (key, value, expires_at)
VALUES (
  'ready_work',
  json_array(
    json_object('id', 1, 'title', 'Fix bug'),
    json_object('id', 2, 'title', 'Add feature')
  ),
  ?  -- expires in 5 minutes
);

-- Query
SELECT
  json_extract(value, '$[0].title') as first_ready_task
FROM beadster_cache
WHERE key = 'ready_work'
  AND expires_at > ?;
```

## Do's and Don'ts

### ✅ Do:

1. **Add custom tables with namespace**
   - `beadster_sync`, `beadster_sessions`, etc.
   - Never `sync`, `sessions` (too generic)

2. **Use foreign keys to issues table**
   - `FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE`
   - Ensures referential integrity

3. **Read Beads tables, write via bd CLI**
   - Read: `SELECT * FROM issues`
   - Write: `bd create`, `bd update`, `bd close`
   - Let Beads maintain its tables

4. **Store metadata in your tables**
   - Sync status, cloud IDs, session tracking
   - Don't pollute Beads tables

5. **Use labels for tagging**
   - `session:xyz`, `client:claude-code`, `project:main-app`
   - Beads natively supports labels

6. **Index your query patterns**
   - Add indexes for performance
   - Composite indexes for complex queries

### ❌ Don't:

1. **Don't modify Beads tables**
   - Never `ALTER TABLE issues ADD COLUMN cloud_id`
   - Beads rebuilds from JSONL, would lose changes

2. **Don't write directly to Beads tables**
   - Use `bd` CLI instead
   - Ensures JSONL and DB stay in sync

3. **Don't duplicate Beads data**
   - Use JOINs instead
   - Keep your tables small

4. **Don't use generic table names**
   - Not: `sync`, `metadata`, `config`
   - Yes: `beadster_sync`, `beadster_metadata`

5. **Don't store large blobs**
   - Keep database fast
   - Store large data elsewhere (cloud, files)

6. **Don't break Beads migrations**
   - Your tables should not interfere with Beads upgrades
   - Use `CREATE TABLE IF NOT EXISTS`

## Extension Lifecycle

### 1. First Time (Post bd init)

```bash
# User runs
cd ~/projects/main-app
bd init

# beadster hook runs (if installed)
beadster init-extension
```

```typescript
// beadster init-extension
async function initExtension() {
  const beadsDir = process.cwd();
  const dbPath = `${beadsDir}/.beads/beads.db`;

  // Create beadster tables
  await beadsterExtension.initialize(beadsDir);

  // Create beadster.json
  fs.writeFileSync(`${beadsDir}/.beads/beadster.json`, JSON.stringify({
    version: '1.0.0',
    source_id: generateSourceId(),
    registered: false,
    sync_enabled: true
  }, null, 2));

  console.log('✓ beadster extension initialized');
}
```

### 2. Ongoing Sync

```typescript
// Sync daemon watches .beads/issues/
class SyncDaemon {
  async watch(beadsDir: string) {
    // Watch for new/changed JSONL files
    fs.watch(`${beadsDir}/.beads/issues`, (eventType, filename) => {
      if (filename.endsWith('.jsonl')) {
        const issueId = filename.replace('.jsonl', '');
        this.syncIssue(issueId);
      }
    });
  }

  async syncIssue(issueId: string) {
    const db = new Database(`${beadsDir}/.beads/beads.db`);

    // Read from Beads
    const issue = db.prepare('SELECT * FROM issues WHERE id = ?').get(issueId);

    // Check our sync status
    const syncStatus = db.prepare(`
      SELECT * FROM beadster_sync WHERE issue_id = ?
    `).get(issueId);

    if (!syncStatus || syncStatus.synced_at < issue.updated_at) {
      // Push to cloud
      await this.cloudAPI.pushIssue(issue);

      // Update our metadata
      db.prepare(`
        INSERT INTO beadster_sync (issue_id, synced_at, sync_status)
        VALUES (?, ?, 'synced')
        ON CONFLICT(issue_id) DO UPDATE SET
          synced_at = excluded.synced_at,
          sync_status = 'synced'
      `).run(issueId, Date.now());
    }
  }
}
```

### 3. Pull from Cloud

```typescript
async function pullCloudChanges() {
  const changes = await cloudAPI.getChanges(since: lastSync);

  for (const change of changes) {
    // Update via bd CLI (Beads handles JSONL + DB)
    execSync(`bd update ${change.id} --title="${change.title}"`);

    // Update our sync metadata
    db.prepare(`
      UPDATE beadster_sync
      SET cloud_updated_at = ?
      WHERE issue_id = ?
    `).run(Date.now(), change.id);
  }
}
```

## Migration Strategy

**When beadster extension updates:**

```typescript
class Migration {
  async migrate(beadsDir: string) {
    const db = new Database(`${beadsDir}/.beads/beads.db`);

    // Check current version
    const version = db.prepare(`
      SELECT value FROM beadster_meta WHERE key = 'version'
    `).get()?.value || '0.0.0';

    if (version < '1.1.0') {
      // Add new column
      db.exec(`
        ALTER TABLE beadster_sync ADD COLUMN last_error TEXT;
      `);

      // Update version
      db.prepare(`
        UPDATE beadster_meta SET value = '1.1.0' WHERE key = 'version'
      `).run();
    }

    if (version < '1.2.0') {
      // Add new table
      db.exec(`
        CREATE TABLE IF NOT EXISTS beadster_webhooks (
          id TEXT PRIMARY KEY,
          url TEXT,
          events TEXT,
          enabled INTEGER DEFAULT 1
        );
      `);

      db.prepare(`
        UPDATE beadster_meta SET value = '1.2.0' WHERE key = 'version'
      `).run();
    }
  }
}
```

## Querying from Mac/iOS Apps

**Apps query local DB directly (when they have access):**

```swift
// Mac app
class beadsterDatabase {
  func getIssues(from beadsPath: URL) -> [Issue] {
    let dbPath = beadsPath.appendingPathComponent("beads.db").path

    let db = try Connection(dbPath)

    let issues = Table("issues")
    let beadsterSync = Table("beadster_sync")

    let query = issues
      .join(.leftOuter, beadsterSync, on: issues[id] == beadsterSync[issue_id])
      .select(issues[*], beadsterSync[cloud_id], beadsterSync[sync_status])
      .order(issues[created_at].desc)

    return try db.prepare(query).map { row in
      Issue(
        id: row[issues[id]],
        title: row[issues[title]],
        status: row[issues[status]],
        cloudId: row[beadsterSync[cloud_id]],
        syncStatus: row[beadsterSync[sync_status]]
      )
    }
  }
}
```

## Storing Security-Scoped Bookmarks

**For sandboxed Mac apps, bookmarks stored in .beads/ database:**

```swift
// When user grants access to folder
class SourceManager {
  func addExternalSource(folderURL: URL) {
    // Get security-scoped bookmark
    guard let bookmark = try? folderURL.bookmarkData(
      options: .withSecurityScope
    ) else {
      return
    }

    let beadsPath = folderURL.appendingPathComponent(".beads")
    let dbPath = beadsPath.appendingPathComponent("beads.db")

    // Check if has .beads/
    if !fileManager.fileExists(atPath: beadsPath.path) {
      // Create .beads/ first
      self.initializeBeads(in: folderURL)
    }

    // Store bookmark in beadster extension table
    let db = try Connection(dbPath.path)

    try db.run("""
      INSERT INTO beadster_source (
        id, name, bookmark, bookmark_updated_at
      )
      VALUES ('1', ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        bookmark = excluded.bookmark,
        bookmark_updated_at = excluded.bookmark_updated_at
    """, folderURL.lastPathComponent,
         bookmark.base64EncodedString(),
         Int(Date().timeIntervalSince1970))

    // Also save to app's sources registry
    self.saveToAppRegistry(folderURL, bookmark: bookmark)
  }

  func saveToAppRegistry(
    _ projectURL: URL,
    bookmark: Data
  ) {
    // App container registry
    let containerURL = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.beadster")!

    let registryPath = containerURL
      .appendingPathComponent("sources.json")

    var registry = loadRegistry(from: registryPath)

    registry.sources.append(Source(
      id: UUID().uuidString,
      name: projectURL.lastPathComponent,
      path: projectURL.path,
      type: "external",
      bookmark: bookmark.base64EncodedString(),
      beadsPath: projectURL.appendingPathComponent(".beads").path
    ))

    saveRegistry(registry, to: registryPath)
  }
}
```

**Restoring access later:**

```swift
class SourceManager {
  func accessSource(beadsPath: URL) -> URL? {
    let dbPath = beadsPath.appendingPathComponent("beads.db")

    guard FileManager.default.fileExists(atPath: dbPath.path) else {
      return nil
    }

    // Read bookmark from beadster extension table
    let db = try? Connection(dbPath.path)

    let query = try? db?.prepare("""
      SELECT bookmark, bookmark_updated_at
      FROM beadster_source
      WHERE id = '1'
    """)

    guard let row = try? query?.first,
          let bookmarkString = row[0] as? String,
          let bookmarkData = Data(base64Encoded: bookmarkString) else {
      return nil
    }

    // Restore access from bookmark
    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      bookmarkDataIsStale: &isStale
    ) else {
      return nil
    }

    if isStale {
      // Bookmark expired, need to re-request access
      return self.repromptForAccess(beadsPath: beadsPath)
    }

    return url
  }

  func repromptForAccess(beadsPath: URL) -> URL? {
    // Show alert to user
    let alert = NSAlert()
    alert.messageText = "Access Expired"
    alert.informativeText = "beadster needs access to this folder again."
    alert.addButton(withTitle: "Grant Access")
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else {
      return nil
    }

    // Open folder picker
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.message = "Select the folder containing .beads/"

    guard panel.runModal() == .OK,
          let url = panel.url else {
      return nil
    }

    // Save new bookmark
    if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
      let dbPath = beadsPath.appendingPathComponent("beads.db")
      let db = try? Connection(dbPath.path)

      try? db?.run("""
        UPDATE beadster_source
        SET bookmark = ?, bookmark_updated_at = ?
        WHERE id = '1'
      """, bookmark.base64EncodedString(), Int(Date().timeIntervalSince1970))
    }

    return url
  }
}
```

**Benefits of storing in .beads/ database:**

1. **Portable** - Bookmark travels with project
2. **Self-contained** - .beads/ directory knows how to be accessed
3. **Multiple apps** - Any beadster app can read the bookmark
4. **Sync-aware** - If .beads/ moves, bookmark can be refreshed

**App registry vs .beads/ database:**

```
~/.Library/Containers/com.beadster/Data/sources.json
- Quick lookup of all sources
- App's view of registered projects

~/projects/main-app/.beads/beads.db (beadster_source table)
- Bookmark for THIS specific source
- Self-contained with project
- Syncs if .beads/ is copied
```

**Discovery flow:**

```
1. App starts
2. Reads sources.json from container
3. For each external source:
   a. Get beadsPath from registry
   b. Open beadsPath/beads.db
   c. Read bookmark from beadster_source table
   d. Restore access using bookmark
   e. Watch for changes
```

**Example:**

```swift
class AppDelegate {
  func applicationDidFinishLaunching() {
    // Load sources from app registry
    let sources = loadSources()

    for source in sources where source.type == "external" {
      // Try to access using saved bookmark
      if let projectURL = accessSource(beadsPath: source.beadsPath) {
        // Success! Start syncing
        syncDaemon.watch(projectURL)
      } else {
        // Bookmark failed, prompt user
        notifySourceInaccessible(source)
      }
    }
  }
}
```

**This solves multiple problems:**

1. ✅ Sandboxed app can persistently access external folders
2. ✅ Bookmark stored with project (not just in app container)
3. ✅ If .beads/ directory is moved, app can detect and re-request
4. ✅ Multiple machines can each store their own bookmarks
5. ✅ No symlinks needed (works in sandbox)

## Summary

**beadster extends Beads following EXTENDING.md guidelines:**

1. ✅ **Add custom tables** (namespaced: `beadster_*`)
2. ✅ **Use foreign keys** to `issues` table
3. ✅ **Store metadata** in our tables, not Beads tables
4. ✅ **Read from Beads**, write via `bd` CLI
5. ✅ **Use labels** for tagging (session, client, project)
6. ✅ **Index query patterns** for performance
7. ✅ **Use JSON** for flexible state

**What we add:**
- Sync metadata (cloud IDs, sync timestamps)
- Session tracking (extracted from labels)
- Conflict resolution
- Source registration
- Cache for performance

**What we don't do:**
- ❌ Modify Beads tables
- ❌ Write directly to Beads DB
- ❌ Duplicate Beads data
- ❌ Break Beads migrations

**Key insight:** Beads stays pure and focused. beadster adds orchestration layers using the recommended extension patterns. Both systems coexist in the same SQLite database harmoniously.
