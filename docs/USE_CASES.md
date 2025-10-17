# BeadsHub Use Cases

## Naming: Not "Personal", It's "Inbox"

You're right - "personal" is a bad name. These could be:
- Company tasks (system operator LLC work)
- NGO tasks (nonprofit projects)
- Random work that doesn't belong to a repo

Better name: **inbox**

```
~/.beadshub/inbox/.beads/
```

This is where ALL non-repo tasks go by default:
- Company admin work
- NGO projects without repos
- Random Claude sessions
- Life tasks
- Planning work

Then you can:
- Leave them in inbox
- Move to specific .beads/ directory later
- Or just filter by labels (company, ngo, personal)

## Virtual Git Repos (Gitlip Approach)

Inspired by https://www.gitlip.com/blog/infinite-git-repos-on-cloudflare-workers

**Problem:** Not every project needs a real git repo, but Beads expects git-like behavior.

**Solution:** Virtual git repos in the cloud.

### For Non-Repo Projects

```bash
# User creates tasks for NGO project (no code repo)
User: "Create task: Update NGO website copy"

# MCP server detects: no local .beads/, not in a git repo
# Instead of using inbox, create virtual repo

beadshub create-source "ngo-website" --type=virtual

# Cloud creates:
- Virtual source ID
- Cloud storage for issues
- Git-like sync API
- But NO local .beads/ required
```

### Architecture

```
Traditional (with git):
.beads/issues/*.jsonl → git → sync daemon → cloud

Virtual (no git):
Cloud API directly → D1 database → (optional) .beads/ local cache
```

### Virtual Sources Table

```sql
CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,        -- 'local-git', 'local-no-git', 'virtual', 'inbox'

  -- For local sources
  path TEXT,                 -- ~/projects/my-app
  machine_id TEXT,
  last_sync INTEGER,

  -- For virtual sources (cloud-only)
  cloud_only BOOLEAN DEFAULT 0,

  -- Common
  first_seen INTEGER,
  issue_count INTEGER,

  FOREIGN KEY (user_id) REFERENCES users(id)
);
```

### MCP Server Logic

```typescript
class BeadsHubMCP {
  async findOrCreateSource() {
    const cwd = process.cwd();

    // 1. Check for local .beads/
    const localBeads = this.findLocalBeads();
    if (localBeads) {
      return { type: 'local', path: localBeads };
    }

    // 2. Check if in a git repo - auto-init here
    if (this.isGitRepo(cwd)) {
      const root = this.findGitRoot();
      execSync(`cd ${root} && bd init`);
      return { type: 'local', path: root };
    }

    // 3. Ask user or use inbox
    const projectName = await this.detectProjectName();

    if (projectName && projectName !== 'unknown') {
      // User is working on something specific
      return await this.promptUserForSource(projectName);
    }

    // 4. Default to inbox
    return { type: 'inbox', path: this.getInboxPath() };
  }

  async promptUserForSource(projectName) {
    // Through Claude
    const response = await this.askUser(
      `You're working on "${projectName}" but there's no git repo. Where should tasks go?\n\n` +
      `1. Create local .beads/ here\n` +
      `2. Create virtual source "${projectName}" (cloud-only)\n` +
      `3. Use inbox (default)`
    );

    if (response === '1') {
      execSync(`cd ${process.cwd()} && bd init`);
      return { type: 'local', path: process.cwd() };
    }

    if (response === '2') {
      await this.createVirtualSource(projectName);
      return { type: 'virtual', name: projectName };
    }

    return { type: 'inbox', path: this.getInboxPath() };
  }

  async createVirtualSource(name) {
    // Create cloud-only source
    await fetch('https://api.beadshub.com/api/sources', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.apiKey}` },
      body: JSON.stringify({
        name,
        type: 'virtual',
        cloud_only: true
      })
    });
  }

  getInboxPath() {
    return path.join(os.homedir(), '.beadshub', 'inbox');
  }
}
```

## Use Cases by User Type

### Type 1: Developer Using bd Manually

**Who:** Technical users who love CLI tools, understand git, use bd directly.

**What they do:**
```bash
cd ~/projects/my-app
bd create "Fix auth bug"
bd create "Add tests" --blocks="Fix auth bug"
bd ready
bd show 42
```

**What BeadsHub adds:**
- Web UI to see all their bd issues across 30+ repos
- Mobile app to check tasks on the go
- Cross-repo search: "Show all auth issues"
- Beautiful dependency visualizations
- Share issues with team (public links)

**Example:**

```
Developer's workflow:
1. Uses bd CLI exclusively for creating/managing issues
2. bd syncs to local .beads/issues/*.jsonl
3. Sync daemon watches, pushes to BeadsHub
4. Developer opens beadshub.com to see big picture
5. Developer on iOS app sees "Ready to work on: 12 issues"
6. Developer clicks issue on phone, sees full context
```

**BeadsHub value:**
- Don't lose bd's power
- Add visibility across all projects
- Add mobile access
- Add beautiful UIs
- Add team collaboration

### Type 2: Agent-First Developer

**Who:** Developers who let Claude manage all task tracking, rarely use bd CLI directly.

**What they do:**
```
User: "Add todo to implement OAuth"
Claude → bd create "Implement OAuth" --label="auth"

User: "What should I work on?"
Claude → bd ready
```

**What BeadsHub adds:**
- Same as Type 1, but agent does all bd commands
- User only interacts via Claude or web UI
- Never types bd commands manually

**Example:**

```
Agent workflow:
1. User talks to Claude Code
2. Claude: "I'll create an issue for this"
3. Claude runs: bd create "Fix bug" --discovered-from="current-issue"
4. User opens beadshub.com later: "Oh, I have 5 new issues from that session"
5. User marks one as high priority in web UI
6. Syncs back to local .beads/
7. Next Claude session: "You have 1 high priority task ready"
```

**BeadsHub value:**
- Visibility into what agent is tracking
- Override agent decisions (change priorities, close issues)
- See history of all sessions
- Understand what agent is thinking

### Type 3: Non-Technical User (Cursor, Windsurf, etc.)

**Who:**
- Designers using Cursor
- Product managers using AI coding tools
- Startup founders using Windsurf
- Anyone using Claude but not coding directly

**What they do:**
- Talk to AI in natural language
- Never use terminal
- Never see bd commands
- Just want tasks to work

**What they need:**
- Beautiful Mac/iOS app
- Simple "Add task" button
- See all tasks in one place
- Mark complete in UI
- No .beads/ directories, no git, no CLI

**BeadsHub approach for them:**

```
Option A: Virtual sources only (no local .beads/)

User opens BeadsHub Mac app
User: "Add task: Review mockups"
→ Creates issue directly in cloud
→ No local .beads/ created
→ Everything lives in cloud
→ Optional: Local cache for offline

Benefits:
- No file system permissions needed
- No .beads/ clutter
- Just works
- Can still use from Cursor/Windsurf via MCP
```

```
Option B: Invisible .beads/ managed by app

BeadsHub Mac app creates ~/.beadshub/managed/.beads/
→ App has write access (one-time permission)
→ All tasks go here by default
→ User never sees it, never thinks about it
→ MCP uses this automatically
→ Syncs to cloud

Benefits:
- Gets bd's power (dependencies, ready work)
- User doesn't need to understand it
- Works offline
- Can switch to Type 1/2 later if they want
```

**Example workflow:**

```
Non-technical user:
1. Opens BeadsHub Mac app
2. Clicks "Add Task"
3. Types: "Update landing page copy"
4. Selects project: "Main Website" (virtual source)
5. Clicks save
6. Task appears in list

Later in Cursor:
User: "What tasks do I have?"
Claude (via MCP) → Reads from BeadsHub cloud
Claude: "You have 1 task: Update landing page copy"

User: "Mark it complete"
Claude → Updates cloud
Mac app auto-refreshes, shows completed
```

**BeadsHub value:**
- Works without understanding bd/git/CLI
- Beautiful native apps
- Just works™
- Can graduate to power features later

### Type 4: Mixed Team

**Who:** Team with both technical and non-technical members.

**Example:**
- Developer (uses bd CLI)
- Designer (uses Mac app)
- PM (uses iOS app)
- Agents (use MCP)

**What they need:**
- Everyone sees same issues
- Different interfaces for different people
- Doesn't matter how issue was created

**BeadsHub approach:**

```
Developer creates via bd CLI:
cd ~/projects/app
bd create "Fix login bug" --label="urgent"
→ Syncs to cloud

Designer sees in Mac app:
"Fix login bug" (urgent)
→ Adds comment: "This affects the new signup flow"
→ Syncs to cloud

PM sees in iOS app:
"Fix login bug" with designer's comment
→ Changes priority to high
→ Syncs to cloud

Agent sees in next Claude session:
"You have 1 urgent, high priority issue: Fix login bug"
→ Starts working on it
→ Creates sub-issues as needed
```

**BeadsHub value:**
- One source of truth
- Multiple interfaces
- Real-time sync
- Everyone stays aligned

## Configuration: User Chooses Default Behavior

Let users configure how they want to work:

```json
// ~/.beadshub/config.json

{
  "default_mode": "local-with-sync",  // or "cloud-only" or "hybrid"

  "local_mode": {
    "auto_init_in_git_repos": true,
    "inbox_path": "~/.beadshub/inbox",
    "auto_discover_sources": true
  },

  "cloud_mode": {
    "virtual_sources_by_default": true,
    "local_cache_enabled": true,
    "local_cache_path": "~/.beadshub/cache"
  },

  "hybrid_mode": {
    "use_local_for_code_projects": true,
    "use_cloud_for_non_code": true
  }
}
```

**Preset 1: Technical Developer (default)**
```json
{
  "default_mode": "local-with-sync",
  "auto_init_in_git_repos": true,
  "inbox_path": "~/.beadshub/inbox"
}
```

**Preset 2: Non-Technical User**
```json
{
  "default_mode": "cloud-only",
  "virtual_sources_by_default": true,
  "local_cache_enabled": true
}
```

**Preset 3: Mixed (your case)**
```json
{
  "default_mode": "hybrid",
  "use_local_for_code_projects": true,
  "use_cloud_for_non_code": true,
  "inbox_path": "~/.beadshub/inbox"
}
```

## Detailed Scenario: Your Workflow

You have:
- 30+ coding projects (want local .beads/)
- Company work (no repo needed)
- NGO work (no repo needed)
- Random Claude sessions

### Setup

```bash
# Install
brew install beadshub

# One-time config
beadshub setup

> Choose mode:
> 1. Developer (local .beads/ + sync)
> 2. Cloud-only (no local files)
> 3. Hybrid (auto-detect)

You choose: 3 (Hybrid)

> Configure inbox path:
> Default: ~/.beadshub/inbox
> [Enter to accept]

You press Enter

> Scan for existing .beads/ directories?
> [Y/n]

You: y

> Found 32 .beads/ directories
> Start syncing? [Y/n]

You: y

> ✓ Setup complete
> ✓ Sync daemon started
> ✓ 342 issues synced to cloud
>
> Open beadshub.com to see everything!
```

### Daily Usage

**Scenario 1: Working on coding project**

```bash
cd ~/projects/main-app
# Has .beads/ already

# Claude creates issue via MCP
Claude: bd create "Fix auth bug"
→ Goes to ~/projects/main-app/.beads/
→ Auto-syncs to cloud
```

**Scenario 2: Company work (no repo)**

```bash
# Random directory
cd ~/Documents

User: "Add task: File Q4 taxes for system operator"

# MCP detects:
# - Not in git repo
# - No local .beads/
# - Hybrid mode configured
# Decision: Use cloud virtual source

Claude: "I'll add this to your inbox. Should I create a 'system-operator-admin' source?"

You: "Yes"

Claude → Creates virtual source in cloud
Claude → Issue goes there
→ No local .beads/ created
→ Pure cloud
```

**Scenario 3: NGO project (no repo)**

```bash
User: "Add task: Update NGO website hero text"

Claude: "Creating virtual source: ngo-website"
→ Virtual source in cloud
→ Issue added
→ No local files
```

**Scenario 4: Random session**

```bash
cd ~/Downloads/temp

User: "Research competitor pricing"

# MCP detects: random location, not important
Claude → Uses inbox (~/.beadshub/inbox/.beads/)
→ Local file created
→ Syncs to cloud
```

### Viewing Everything

**BeadsHub web app:**

```
beadshub.com

All Sources (35)

Code Projects (32):
  main-app (23 issues)
  side-project (5 issues)
  ...

Virtual Sources (2):
  system-operator-admin (3 issues)
  ngo-website (1 issue)

Inbox (12 issues)

---

Total: 387 issues
Open: 156
Ready to work on: 42
```

**Filter by type:**

```
Show: [Code projects ▼]
→ Only your 32 repos

Show: [Company & NGO ▼]
→ Only virtual sources

Show: [Inbox ▼]
→ Only random stuff
```

### Moving Tasks

```
Issue in inbox: "Plan new feature"

User realizes: This should be in main-app project

In web UI:
[Move to...] → main-app

Result:
- If main-app is local: Issue moves to ~/projects/main-app/.beads/
- If main-app is virtual: Issue moves to that virtual source
- Sync daemon handles the move
```

## Summary

**Core insight:** Not everything needs a git repo or local .beads/ directory.

**Three types of sources:**

1. **Local with git** (coding projects)
   - .beads/ directory in project
   - Git-backed
   - Full bd power
   - Syncs to cloud

2. **Virtual sources** (non-code projects)
   - Company work
   - NGO projects
   - Design projects
   - No local .beads/ required
   - Cloud-first
   - Optional local cache

3. **Inbox** (random stuff)
   - ~/.beadshub/inbox/.beads/
   - Everything that doesn't fit elsewhere
   - Can move to other sources later
   - Or just stay in inbox forever

**For non-technical users:**
- Can use BeadsHub without ever seeing .beads/ directories
- Mac/iOS apps create virtual sources
- Everything in cloud
- Optional local cache for offline
- Can graduate to local .beads/ later if they want

**For developers:**
- Full bd CLI power
- .beads/ directories where they want them
- Sync daemon handles everything
- Web/mobile apps add visibility

**For your case:**
- Hybrid mode
- Local .beads/ for code projects
- Virtual sources for company/NGO
- Inbox for random sessions
- BeadsHub aggregates everything

Want me to design the virtual source API and sync protocol?
