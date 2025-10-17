# BeadsHub - Complete Integration with All Original Features

## What We're Building

BeadsHub = bd (Beads) + ALL your original todo system features + Cloud sync

**Everything from your original spec PLUS Beads benefits!**

## All Your Original Features - Preserved

### 1. Screenshot Context Capture ✅

```typescript
// MCP server captures screenshots (via macuse app)
async function todo_create(params) {
  const context = {
    file: getCurrentFile(),
    line: getCurrentLine(),
    screenshot: await captureScreenshot(),  // From macuse app!
    git_branch: await getGitBranch()
  };

  // Store as Beads label + cloud metadata
  bd create "${params.title}" \
    --label="file:${context.file}" \
    --label="line:${context.line}" \
    --label="screenshot:${context.screenshot}"
}
```

**Sync daemon pushes screenshot ID to cloud:**
```typescript
await cloudAPI.upsertIssue({
  ...issue,
  context_screenshot: extractLabel(issue, 'screenshot')
});
```

**Web UI shows screenshot:**
```
beadshub.com/issues/54

#54 Fix login bug

Context:
📁 auth.js:42
🌿 feature/auth-fixes
📸 [View Screenshot] ← Loads from S3/R2
```

### 2. Task Panel UI Integration ✅

```swift
// macOS app (FC/macuse) with task panel

class TaskPanelViewModel: ObservableObject {
    @Published var issues: [Issue] = []

    func load() async {
        // Option 1: Load from local Beads
        let localIssues = execSync("bd list --json")

        // Option 2: Load from BeadsHub cloud
        let cloudIssues = await fetchFromBeadsHub()

        issues = merge(localIssues, cloudIssues)
    }
}

// Task Panel shows:
┌─────────────────────────────┐
│ 🎯 Tasks              [−][×]│
├─────────────────────────────┤
│ ▼ Ready Work (3)            │
│                              │
│ #54 Fix login bug        🔴 │
│   auth.js:42                 │
│   [View] [Complete]          │
│                              │
│ #55 Add rate limiting    🟡 │
│   (blocked by #54)           │
│                              │
│ ▼ By Session                │
│                              │
│ 💻 Claude Code (Today)      │
│   #54, #55, #56 (3 issues)  │
│                              │
│ 📱 Claude iOS (Yesterday)   │
│   #52, #53 (2 issues)        │
└─────────────────────────────┘
```

### 3. Apple Reminders Sync ✅

```typescript
// Sync daemon watches for deadlines
class SyncDaemon {
  async syncToAppleReminders(issue) {
    if (issue.deadline) {
      await appleScript(`
        tell application "Reminders"
          make new reminder with properties {
            name: "${issue.title}",
            body: "${issue.body}",
            due date: date "${issue.deadline}",
            remind me date: date "${issue.deadline}"
          }
        end tell
      `);
    }
  }

  async watchAppleReminders() {
    // Poll for completed reminders
    const completed = await getCompletedReminders();
    for (const reminder of completed) {
      const issue = findIssueByTitle(reminder.name);
      if (issue) {
        // Mark in Beads
        execSync(`bd close "${issue.id}"`);
        // Sync to cloud
        await cloudAPI.closeIssue(issue.id);
      }
    }
  }
}
```

### 4. Alto.inded Integration ✅

```typescript
// Optional sync to alto.inded
if (config.sync_to_alto) {
  await alto.notes.create({
    title: `TODO: ${issue.title}`,
    content: issue.body,
    tags: issue.labels,
    folder: "beadshub"
  });
}

// Bidirectional
const altoNotes = await alto.notes.list({ folder: "beadshub" });
for (const note of altoNotes) {
  if (!existsInBeads(note)) {
    bd create "${note.title}" --body="${note.content}"
  }
}
```

### 5. Session Tracking - ALL Cases ✅

**Your exact use cases:**

**Case A: "Show 3 todos from one Claude session on project-a"**
```bash
User: "Show todos from this conversation on project-a"

Claude → todo_list({
  session_id: getCurrentSessionId(),
  project: "project-a"
})

BeadsHub: Filters by labels:
- session:session_abc123
- project:project-a

Returns: 3 issues
```

**Case B: "Show 2 todos from another session on project-b"**
```bash
User: "Show todos from my afternoon session on project-b"

Claude → todo_list({
  session_id: "session_def456",  // From session history
  project: "project-b"
})

Returns: 2 issues
```

**Case C: "Show todos from Claude iOS"**
```bash
User: "What did I save from my iPhone?"

Claude → todo_list({
  client: "claude-mobile"
})

BeadsHub: Filters by label:
- client:claude-mobile

Returns: All iOS issues
```

**Case D: "Show EVERYTHING"**
```bash
User: "Show all my todos"

Claude → todo_list({ source: "all" })

BeadsHub cloud: Returns ALL issues from ALL sources
```

**Case E: "Group by session"**
```bash
User: "Show me todos grouped by when I created them"

Claude → todo_list({ group_by: "session" })

Response:
{
  "session_abc123": [
    {"title": "Fix bug", ...},
    {"title": "Add tests", ...},
    {"title": "Deploy", ...}
  ],
  "session_def456": [
    {"title": "Review PR", ...},
    {"title": "Update docs", ...}
  ]
}
```

### 6. Context File/Line Capture ✅

```typescript
// MCP auto-captures file context
async function todo_create(params) {
  const context = {
    file: getCurrentFile(),           // /Users/anton/project/auth.js
    line: getCurrentLine(),           // 42
    code_snippet: getSelectedText(),  // if (token.expired()) { ...
    working_directory: process.cwd()
  };

  // Store in Beads via labels
  bd create "${params.title}" \
    --label="file:${path.basename(context.file)}" \
    --label="line:${context.line}"

  // Sync daemon extracts and pushes full context to cloud
  await cloudAPI.upsertIssue({
    ...issue,
    context_file: context.file,
    context_line: context.line,
    context_code: context.code_snippet
  });
}
```

**Click issue in web UI:**
```
#54 Fix login bug

Context:
📁 auth.js:42
```

Click "Jump to code" → `vscode://file/Users/anton/project/auth.js:42`

### 7. Priority Detection ✅

```typescript
// MCP auto-detects priority
function detectPriority(title, body) {
  const text = `${title} ${body}`.toLowerCase();

  const highKeywords = ['urgent', 'asap', 'critical', 'bug', 'broken', 'production'];
  const lowKeywords = ['someday', 'maybe', 'nice to have', 'eventually'];

  if (highKeywords.some(kw => text.includes(kw))) {
    return 'high';
  }
  if (lowKeywords.some(kw => text.includes(kw))) {
    return 'low';
  }
  return 'medium';
}

// Use in Beads
bd create "${title}" --priority=${detectPriority(title, body)}
```

### 8. Auto-Tagging ✅

```typescript
function autoTag(params) {
  const tags = new Set(params.labels || []);

  // Tag by file extension
  if (params.context?.file) {
    const ext = path.extname(params.context.file);
    if (ext === '.js') tags.add('javascript');
    if (ext === '.py') tags.add('python');
  }

  // Tag by keywords
  const text = `${params.title} ${params.body}`.toLowerCase();
  if (text.includes('bug')) tags.add('bug');
  if (text.includes('test')) tags.add('testing');
  if (text.includes('doc')) tags.add('documentation');

  return Array.from(tags);
}
```

### 9. Deadline Parsing ✅

```typescript
function parseDeadline(input) {
  const patterns = {
    'today': () => moment().endOf('day'),
    'tomorrow': () => moment().add(1, 'day').endOf('day'),
    'next week': () => moment().add(1, 'week').startOf('week'),
    'in 2 hours': () => moment().add(2, 'hours')
  };

  for (const [pattern, fn] of Object.entries(patterns)) {
    if (input.toLowerCase().includes(pattern)) {
      return fn().toISOString();
    }
  }
  return null;
}

// Usage
User: "Add todo to call John tomorrow"

Claude:
bd create "Call John" --label="deadline:${parseDeadline('tomorrow')}"
```

### 10. Statistics & Analytics ✅

```typescript
// MCP tool
async function todo_stats(params) {
  // Query cloud for rich analytics
  const stats = await cloudAPI.getStats({
    period: params.period,
    user_id: getCurrentUser()
  });

  return {
    total: stats.total,
    pending: stats.pending,
    completed: stats.completed,
    by_priority: stats.by_priority,
    by_project: stats.by_project,
    by_session: stats.by_session,  // NEW: Group by session
    by_client: stats.by_client,    // NEW: Group by client
    completion_rate: stats.completion_rate,
    avg_completion_time: stats.avg_completion_time
  };
}
```

**Web UI:**
```
beadshub.com/stats

📊 Your Stats (This Week)

Total: 47 issues
Completed: 33 (70%)
Pending: 14

By Priority:
🔴 High: 3
🟡 Medium: 8
🟢 Low: 3

By Client:
💻 Claude Code: 25
🖥️ Claude Desktop: 15
📱 Claude Mobile: 7

By Project:
project-a: 18 issues
project-b: 12 issues
personal: 17 issues

By Session:
5 sessions this week
Avg 9.4 issues per session
```

### 11. Smart Suggestions ✅

```typescript
async function todo_create(params) {
  // Create issue
  const issue = await bd.create(params);

  // Find related issues
  const related = await findRelated(issue);

  if (related.length > 0) {
    return {
      issue,
      suggestions: {
        message: `Found ${related.length} related issues:`,
        issues: related.map(i => ({
          id: i.id,
          title: i.title,
          reason: explainRelation(issue, i)
        }))
      }
    };
  }
}

function findRelated(issue) {
  const allIssues = loadAllIssues();

  return allIssues.filter(other => {
    // Same file
    if (other.context?.file === issue.context?.file) return true;

    // 2+ shared tags
    const sharedLabels = intersection(other.labels, issue.labels);
    if (sharedLabels.length >= 2) return true;

    // Similar title
    if (similarity(other.title, issue.title) > 0.7) return true;

    return false;
  });
}
```

### 12. Export & Backup ✅

```typescript
// Export from cloud
GET /api/export?format=json
GET /api/export?format=csv
GET /api/export?format=md

// Automatic backups
class SyncDaemon {
  async backup() {
    // Backup local Beads
    for (const repo of this.repos) {
      execSync(`cd ${repo.path} && git add .beads && git commit -m "backup"`);
    }

    // Backup cloud
    const allIssues = await cloudAPI.getAllIssues();
    fs.writeFileSync(
      `~/.beadshub/backups/backup_${Date.now()}.json`,
      JSON.stringify(allIssues, null, 2)
    );
  }
}
```

## All Your Original MCP Tools - Enhanced with Beads

### todo_create ✅

```typescript
{
  name: 'todo_create',
  description: 'Create todo (stored in Beads + synced to cloud)',
  parameters: {
    title: { type: 'string', required: true },
    body: { type: 'string' },
    priority: { type: 'string', enum: ['low', 'medium', 'high'] },
    tags: { type: 'array' },
    project: { type: 'string' },
    deadline: { type: 'string' },
    context: {
      type: 'object',
      properties: {
        file: { type: 'string' },
        line: { type: 'number' },
        screenshot_id: { type: 'string' }
      }
    },
    // Beads-specific
    blocks: { type: 'string' },
    parent: { type: 'string' }
  }
}
```

### todo_list ✅

```typescript
{
  name: 'todo_list',
  parameters: {
    // Your original filters
    status: { enum: ['all', 'pending', 'completed'] },
    project: { type: 'string' },
    tags: { type: 'array' },
    priority: { enum: ['low', 'medium', 'high'] },

    // Session tracking (your original feature)
    session_id: { type: 'string' },
    client: { enum: ['claude-code', 'claude-desktop', 'claude-mobile'] },

    // Grouping (your original feature)
    group_by: { enum: ['none', 'session', 'project', 'priority', 'client'] },

    // Context filters (your original feature)
    context_file: { type: 'string' },

    // Beads-specific
    ready_only: { type: 'boolean' }  // Only unblocked issues
  }
}
```

### todo_complete ✅

Same as your original, works with both Beads and cloud.

### todo_update ✅

Same as your original, works with both Beads and cloud.

### todo_delete ✅

Same as your original, soft delete in both Beads and cloud.

### todo_ready ✅

```typescript
// Your original + Beads dependency tracking
{
  name: 'todo_ready',
  description: 'Show ready work (no blockers)',
  parameters: {
    source: { type: 'string' }  // Specific repo or "all"
  }
}

// Returns issues with:
// - status = open
// - blocked_by = null or []  ← Beads dependency tracking!
```

### todo_list_by_session ✅

Your original feature, unchanged:

```typescript
{
  name: 'todo_list_by_session',
  parameters: {
    session_id: { type: 'string' },
    client: { type: 'string' }
  }
}
```

### todo_session_stats ✅

Your original feature, enhanced:

```typescript
{
  name: 'todo_session_stats',
  parameters: {
    session_id: { type: 'string' }
  }
}

// Returns:
{
  session_id: "...",
  client: "claude-code",
  project: "project-a",
  todos_created: 5,
  todos_completed: 2,
  todos_pending: 3,
  tags_used: ["bug", "auth"],
  priority_breakdown: { high: 2, medium: 2, low: 1 },

  // NEW: Beads features
  blocked_count: 1,
  ready_count: 2,
  dependency_tree: [...]
}
```

### todo_stats ✅

Your original feature, unchanged.

## Complete Data Model

### Issue Storage (combines both)

**In local Beads (.beads/issues/issue-54.jsonl):**
```jsonl
{"id":"54","title":"Fix login bug","status":"open","priority":"high","created_at":1729180234}
{"id":"54","labels":["session:abc123","client:claude-code","project:project-a","bug","auth"]}
{"id":"54","body":"Users getting logged out..."}
```

**In cloud (BeadsHub D1):**
```sql
INSERT INTO issues VALUES (
  '54',
  'user_123',
  'source_project_a',

  -- Beads fields
  'Fix login bug',
  'Users getting logged out...',
  'open',
  'high',
  '["bug","auth"]',  -- labels

  -- Your original features
  'session_abc123',   -- session tracking
  'claude-code',      -- client tracking
  'project-a',        -- project tracking
  '/Users/anton/project/auth.js',  -- context file
  42,                 -- context line
  'screenshot_089.png',  -- context screenshot

  -- Timestamps
  1729180234,
  1729180234,
  NULL
);
```

## Web UI - All Your Original Features

```typescript
// beadshub.com

export async function load({ url }) {
  const session = url.searchParams.get('session');
  const client = url.searchParams.get('client');
  const project = url.searchParams.get('project');

  const issues = await db.query(`
    SELECT * FROM issues
    WHERE user_id = ?
    ${session ? 'AND session_id = ?' : ''}
    ${client ? 'AND client = ?' : ''}
    ${project ? 'AND project_name = ?' : ''}
    ORDER BY created_at DESC
  `, [userId, session, client, project].filter(Boolean));

  return { issues };
}
```

**UI:**
```
beadshub.com

┌────────────────────────────────────────────┐
│ BeadsHub                            [User] │
├────────────────────────────────────────────┤
│                                            │
│ Filters:                                   │
│ Session: [All ▼]                          │
│ Client:  [All ▼]                          │
│ Project: [All ▼]                          │
│ Status:  [Open ▼]                         │
│                                            │
│ [Search...]                                │
│                                            │
├────────────────────────────────────────────┤
│                                            │
│ Ready to Work On (5)                       │
│                                            │
│ #54 Fix login bug [high] 🔴               │
│   project-a • auth.js:42                  │
│   Created in Claude Code session (today)  │
│   📸 [View Screenshot]                     │
│   [View Code] [Complete]                  │
│                                            │
│ #55 Add rate limiting [medium] 🟡         │
│   project-a                                │
│   [View] [Complete]                       │
│                                            │
│ ────────────────────────────────           │
│                                            │
│ By Session                                 │
│                                            │
│ 💻 Claude Code - Today 10:15 AM           │
│   project-a (3 issues)                    │
│   #54, #55, #56                           │
│   [View All]                              │
│                                            │
│ 📱 Claude iOS - Yesterday                 │
│   personal (2 issues)                     │
│   #52, #53                                │
│   [View All]                              │
│                                            │
│ ────────────────────────────────           │
│                                            │
│ All Projects (342 issues total)            │
│                                            │
│ project-a (85 issues, 12 open)            │
│ project-b (43 issues, 5 open)             │
│ personal (124 issues, 18 open)            │
│ [Show all 27 more projects...]            │
│                                            │
└────────────────────────────────────────────┘
```

## Summary - EVERYTHING Preserved!

✅ **Your Original Features:**
- Screenshot context capture
- Task panel UI (macOS app)
- Apple Reminders sync
- Alto.inded integration
- Session tracking (session ID, client, project)
- Context file/line capture
- Priority detection
- Auto-tagging
- Deadline parsing
- Statistics & analytics
- Smart suggestions
- Export & backup
- All MCP tools (todo_create, todo_list, etc.)
- Group by session
- Filter by client
- Cross-session queries

✅ **Beads Features Added:**
- Dependency tracking (blocks, blocked_by, parent)
- Ready work detection (unblocked issues)
- Git-backed storage
- Distributed by design
- Semantic compaction
- bd CLI compatibility

✅ **Cloud Features Added:**
- Web UI
- iOS/macOS apps
- Real-time sync
- Cross-device access
- Aggregate view of ALL repos/sources

**Nothing dropped. Everything enhanced!**
