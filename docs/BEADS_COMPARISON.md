# Beads vs macuse Todo System Comparison

## Overview

Steve Yegge's Beads and our macuse todo system solve similar problems but with different approaches.

## What is Beads?

**Beads** is a git-backed issue tracker designed specifically for AI coding agents.

Key concept: "Give your coding agent a memory upgrade"

**Core features:**
- Graph-based issue tracker with 4 dependency types
- Git-backed (JSONL files stored in `.beads/` directory)
- SQLite database built from git log
- Distributed - agents across machines share one logical database
- Semantic compaction - old issues get compressed
- CLI tool: `bd` (beads CLI)
- MCP server: `beads-mcp` for Claude Desktop/Code

**Philosophy:**
> "Agents simply cannot keep track of work using Markdown files. They try, and they try, and they will churn out gobs of six-phase markdown todo-plans in projects until the cows come home."

Beads solves agent amnesia when dealing with complex nested plans.

## macuse Todo System

Our todo system is broader - designed for personal task management across all Claude sessions (Desktop, Code, Mobile, Web).

**Core features:**
- Web service or local JSON storage
- Session tracking (which Claude client created todo)
- Project detection
- Context capture (file, line, screenshot, git branch)
- Multi-platform sync (Mac app, web UI, iOS)
- Integration with Apple Reminders, Calendar
- Task panel UI in macOS app

**Philosophy:**
Persistent todos across all Claude contexts - coding, planning, life tasks, mobile notes.

## Key Differences

| Aspect | Beads | macuse Todo |
|--------|-------|-------------|
| **Focus** | Coding projects only | All tasks (coding + life + work) |
| **Storage** | Git (JSONL) + SQLite | Web API or local JSON |
| **Scope** | Per-project | Global across all projects |
| **Dependencies** | 4 types (blocks, related, parent-child, discovered-from) | Simple (related_todos array) |
| **Session tracking** | Per-repo git history | Per-conversation session ID |
| **Platform** | Coding agents (Claude Code, Amp) | All Claude platforms (Desktop, Code, Mobile, Web) |
| **Sync** | Git push/pull | HTTP API or file sync |
| **UI** | CLI (`bd`) + agent queries | macOS task panel + web UI |
| **Hierarchy** | Tree with epics and blockers | Flat with tags and projects |
| **Context** | Git repo context | File + screenshot + conversation |

## What Beads Does Better

### 1. Dependency Management

Beads has sophisticated dependency tracking:

```bash
# Create issue
bd create "Implement login" --epic="Auth System"

# Create blocking issue
bd create "Set up database" --blocks="Implement login"

# Create discovered work
bd create "Add rate limiting" --discovered-from="Implement login"

# Query ready work (no blockers)
bd ready
```

**Four dependency types:**
- `blocks` - this must be done before that
- `related` - issues that are connected
- `parent-child` - epic → sub-issues
- `discovered-from` - work found while doing other work

Our system: Simple `related_todos` array, no blocking logic.

### 2. Git-Backed Storage

Beads stores issues as JSONL files in `.beads/issues/`:

```
.beads/
├── issues/
│   ├── issue-1.jsonl
│   ├── issue-2.jsonl
│   └── issue-3.jsonl
└── beads.db (SQLite rebuilt from JSONL)
```

**Benefits:**
- ✅ Version control for issues
- ✅ Distributed via git (no server needed)
- ✅ Agents across machines share same database
- ✅ Audit trail via git log
- ✅ Merge conflicts handled by git

Our system: Centralized web service or local JSON - requires HTTP or file sync.

### 3. Ready Work Detection

Agents can instantly query what's ready to work on:

```bash
bd ready --json

# Returns only issues with no open blockers
```

This solves agent orientation: "What should I work on next?"

Our system: No automatic ready detection, agent must filter manually.

### 4. Semantic Compaction

Old closed issues get compressed to save agent context:

```
Issue #42 (closed 30 days ago):
[Full description: "Implemented user authentication with OAuth2, added tests, deployed to staging..."]

After compaction:
Issue #42: "Auth OAuth2 implementation - completed"
```

Keeps issue database lightweight while preserving history in git.

Our system: No compaction, all todos stay full size.

### 5. Agent Autonomy

Beads encourages agents to autonomously file issues:

```markdown
# In CLAUDE.md
We track work in Beads. When you notice work:
- Run `bd create` to file it
- Use --discovered-from to link it
- Agents manage all issues
```

Agents spontaneously file issues as they discover work.

Our system: User-initiated todos, not autonomous agent filing.

## What macuse Todo Does Better

### 1. Cross-Platform Sync

Works across all Claude platforms:

```
Claude Code (Mac) → todo_add → Web API
                                    ↓
Claude Desktop (Mac) ← Web API ← Database
                                    ↓
Claude Mobile (iOS) ← Web API ←─────┘
```

Beads: Per-repo only, requires git push/pull between machines.

### 2. Rich Context Capture

Captures full session context:

```json
{
  "todo": "Fix login bug",
  "context": {
    "file": "/Users/anton/project/auth.js",
    "line": 42,
    "screenshot": "screenshot_089.png",
    "git_branch": "feature/auth-fixes",
    "conversation_id": "conv_xyz"
  },
  "session": {
    "client": "claude-code",
    "platform": "macos",
    "project": "main-app"
  }
}
```

Beads: Git context only, no screenshots or conversation tracking.

### 3. Non-Coding Tasks

Handles all types of todos:

```
- Fix auth bug (coding)
- Call John tomorrow (personal)
- Review design mockups (work)
- Buy groceries (life)
```

Beads: Coding projects only.

### 4. Visual Task Panel

macOS app shows floating task panel:

```
┌─────────────────────────────┐
│ 🎯 Tasks              [−][×]│
├─────────────────────────────┤
│ ▼ Active (3)                │
│                              │
│ ⏳ Installing Postgres       │
│ ⏰ Call John (in 15 min)    │
│ 🔄 Downloading files         │
└─────────────────────────────┘
```

Beads: CLI only (though agents can query and report).

### 5. Session Grouping

View todos by where they were created:

```
User: "Show todos from my phone"

Claude → todo_list(client: "claude-mobile")

Response:
• Review mockups (iOS, yesterday)
• Call John (iOS, today)
```

Beads: No session tracking across different Claude clients.

### 6. Integration with macOS

- Syncs to Apple Reminders
- Syncs to Calendar (deadlines)
- Integration with alto.inded (Notes, Mail, iMessage)
- Task panel UI always visible

Beads: CLI tool only, no OS integration.

## Can They Work Together?

**Yes!** They're complementary:

### Option 1: Beads for Coding, macuse for Everything Else

```markdown
# CLAUDE.md

Coding tasks: Use Beads (`bd create`, `bd ready`)
Other tasks: Use macuse MCP (`todo_add`, `todo_list`)

Example:
- "Add auth tests" → bd create (coding)
- "Call John tomorrow" → todo_add (personal)
- "Review PR #42" → bd create (coding)
- "Buy groceries" → todo_add (life)
```

### Option 2: Sync Beads Issues to macuse

Create MCP tool that bridges them:

```javascript
// In macuse MCP server
async function syncBeadsIssues() {
  // Run: bd list --json
  const beadsIssues = JSON.parse(execSync('bd list --json'));

  // Import to macuse todos
  for (const issue of beadsIssues) {
    await todo_add({
      title: issue.title,
      description: issue.description,
      project: getRepoName(),
      tags: ['beads', ...extractTags(issue)],
      metadata: {
        beads_id: issue.id,
        beads_status: issue.status
      }
    });
  }
}
```

Now you can:
- View Beads issues in macOS task panel
- Access coding issues from Claude Mobile
- Sync to Apple Reminders

### Option 3: macuse Reads Beads, Doesn't Write

macuse MCP server provides read-only access to Beads:

```javascript
// MCP tool: beads_ready
async function beads_ready() {
  const output = execSync('bd ready --json').toString();
  return JSON.parse(output);
}

// MCP tool: beads_show
async function beads_show({ id }) {
  const output = execSync(`bd show ${id} --json`).toString();
  return JSON.parse(output);
}
```

Agents write to Beads directly, but macuse can read and display.

## Architecture Comparison

### Beads Architecture

```
Coding Agent
    ↓
bd CLI (Go binary)
    ↓
SQLite database (rebuilt from JSONL)
    ↑
Git repository (.beads/issues/*.jsonl)
    ↑
Git sync (push/pull)
    ↑
Other machines (agents share via git)
```

**Pros:**
- ✅ No server needed
- ✅ Works offline
- ✅ Git versioning
- ✅ Distributed by design

**Cons:**
- ❌ Requires git sync
- ❌ Per-repo only
- ❌ CLI-focused

### macuse Architecture

```
Claude (any platform)
    ↓
MCP Server (local)
    ↓
HTTP API (web service)
    ↓
Database (PostgreSQL/SQLite)
    ↑
    ├→ macOS App (Task Panel)
    ├→ Web UI
    └→ iOS App
```

**Pros:**
- ✅ Cross-platform
- ✅ Real-time sync
- ✅ Visual UI
- ✅ All task types

**Cons:**
- ❌ Requires server
- ❌ Network dependency
- ❌ No git versioning

## Lessons from Beads

### 1. Agent-First Design

Beads was designed FOR agents, not humans:

> "You don't use Beads directly as a human. Your coding agent will file and manage issues on your behalf."

**Takeaway:** Our MCP tools should be optimized for Claude, not just expose human-friendly features.

### 2. Autonomous Issue Filing

Agents spontaneously create issues:

```
Agent discovers bug while coding
→ Automatically: bd create "Fix XYZ" --discovered-from="current issue"
→ Continues working
```

**Takeaway:** We could add `auto_capture_todos` mode where Claude automatically files todos when it notices work.

### 3. Ready Work is Critical

The `bd ready` command is crucial:

```bash
bd ready
# Shows only issues ready to work on (no blockers)
```

Agents use this to orient themselves after context loss.

**Takeaway:** Add `todo_ready` MCP tool that filters by:
- No dependencies
- Matches current project
- Has deadline or high priority

### 4. Dependency Graphs Matter

Complex projects need dependency tracking:

```
Epic: "Auth System"
  ├─ "Set up database" (blocking)
  ├─ "Implement login" (blocked by database)
  │   └─ "Add rate limiting" (discovered during login)
  └─ "Add OAuth" (related)
```

**Takeaway:** Add basic blocking to our system:
```json
{
  "todo": "Implement login",
  "blocked_by": ["todo_123"],
  "status": "blocked"  // auto-calculated
}
```

### 5. Git as Database is Brilliant

Beads uses git for:
- Version control
- Distribution
- Audit trail
- Conflict resolution
- Offline support

**Takeaway:** We could offer git-backed mode as alternative to web service:
```
~/.macuse/todos/
├── session_xyz.jsonl
├── session_abc.jsonl
└── sessions.jsonl
```

Commit after every todo change, sync via git.

## Recommended Integration

**Best approach:** Use both systems together!

### For Coding Projects

Use Beads:
```bash
# Initialize in project
bd init

# In CLAUDE.md
Use Beads for all coding tasks:
- File issues with `bd create`
- Query ready work with `bd ready`
- Track dependencies
```

### For Everything Else

Use macuse:
```markdown
# In global Claude settings
Use macuse MCP for non-coding tasks:
- Personal todos
- Meeting reminders
- Cross-device tasks
- Life management
```

### Bridge Them

macuse MCP server includes Beads integration:

```javascript
// macuse MCP server provides both
{
  "tools": [
    // macuse tools
    "todo_add",
    "todo_list",
    "todo_complete",

    // Beads wrapper tools
    "beads_create",
    "beads_ready",
    "beads_show",

    // Bridge tool
    "sync_beads_to_todos"
  ]
}
```

## Summary

**Beads strengths:**
- ✅ Perfect for coding projects
- ✅ Sophisticated dependency management
- ✅ Git-backed, distributed
- ✅ Agent-first design
- ✅ Ready work detection

**macuse strengths:**
- ✅ Cross-platform sync
- ✅ All task types (coding + life)
- ✅ Rich context (screenshots, conversations)
- ✅ Visual UI (task panel)
- ✅ OS integration (Reminders, Calendar)

**Recommendation:**
Build macuse MCP server to:
1. Provide general todo system (like planned)
2. Detect if Beads is available (`bd` in PATH)
3. Use Beads for coding tasks automatically
4. Use macuse for everything else
5. Optional: Sync Beads issues to macuse for visibility

Best of both worlds!

## Code to Integrate Beads

```typescript
// In macuse MCP server

class TodoService {
  async addTodo(params) {
    // Check if this is a coding task in a Beads-enabled repo
    if (await this.isBeadsRepo() && this.isCodingTask(params)) {
      return await this.useBeads(params);
    }

    // Otherwise use macuse
    return await this.useMacuse(params);
  }

  async isBeadsRepo() {
    try {
      execSync('bd list', { stdio: 'ignore' });
      return true;
    } catch {
      return false;
    }
  }

  isCodingTask(params) {
    // Has file context or coding-related tags
    return params.context?.file ||
           params.tags?.some(t => ['bug', 'feature', 'test', 'refactor'].includes(t));
  }

  async useBeads(params) {
    const cmd = `bd create "${params.title}"`;
    const flags = [];

    if (params.priority === 'high') flags.push('--priority=high');
    if (params.description) flags.push(`--body="${params.description}"`);

    const output = execSync(`${cmd} ${flags.join(' ')} --json`).toString();
    return JSON.parse(output);
  }

  async useMacuse(params) {
    // Use web API or local JSON
    return await this.webService.addTodo(params);
  }
}
```

This way users get best of both worlds automatically!
