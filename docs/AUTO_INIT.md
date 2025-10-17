# Auto-Creating .beads/ Directories

## Problem

You have 30+ projects and random Claude sessions. Do you need to manually run `bd init` everywhere?

**Answer: No!** Multiple strategies for auto-creation.

## Strategy 1: MCP Server Auto-Init (Recommended)

The BeadsHub MCP server automatically initializes `.beads/` when needed:

```typescript
class BeadsHubMCP {
  async todo_create(params) {
    const beadsDir = await this.findOrCreateBeadsDir();
    // ... create issue
  }

  async findOrCreateBeadsDir() {
    const cwd = process.cwd();

    // 1. Check current directory
    if (fs.existsSync(`${cwd}/.beads`)) {
      return cwd;
    }

    // 2. Check parent directories (like git does)
    let dir = cwd;
    while (dir !== '/' && dir.length > 1) {
      if (fs.existsSync(`${dir}/.beads`)) {
        return dir;
      }
      dir = path.dirname(dir);
    }

    // 3. Decide: auto-create or use default?

    // Option A: Auto-create in current directory (if it's a git repo)
    if (this.isGitRepo(cwd)) {
      console.log(`Initializing .beads/ in ${cwd}`);
      execSync(`cd ${cwd} && bd init`, { stdio: 'inherit' });
      return cwd;
    }

    // Option B: Auto-create in project root (if we can detect it)
    const projectRoot = await this.findProjectRoot(cwd);
    if (projectRoot) {
      console.log(`Initializing .beads/ in ${projectRoot}`);
      execSync(`cd ${projectRoot} && bd init`, { stdio: 'inherit' });
      return projectRoot;
    }

    // Option C: Use default personal directory
    const defaultDir = path.join(os.homedir(), '.beadshub', 'personal');
    if (!fs.existsSync(`${defaultDir}/.beads`)) {
      fs.mkdirSync(defaultDir, { recursive: true });
      execSync(`cd ${defaultDir} && bd init`, { stdio: 'inherit' });
    }
    return defaultDir;
  }

  isGitRepo(dir) {
    return fs.existsSync(`${dir}/.git`);
  }

  async findProjectRoot(dir) {
    // Look for indicators of project root
    const indicators = [
      'package.json',
      'Cargo.toml',
      'go.mod',
      'pyproject.toml',
      '.git',
      'pom.xml'
    ];

    let current = dir;
    while (current !== '/' && current.length > 1) {
      for (const indicator of indicators) {
        if (fs.existsSync(path.join(current, indicator))) {
          return current;
        }
      }
      current = path.dirname(current);
    }

    return null;
  }
}
```

**Result:**
- Agent creates first todo → MCP auto-creates `.beads/` in right place
- No manual `bd init` needed
- Smart detection of project root

## Strategy 2: Hook-Based Auto-Init

Use Claude Code hooks to auto-init when session starts:

```bash
# ~/.claude/hooks/session-start.sh
#!/bin/bash

# Check if current directory has .beads
if [ ! -d ".beads" ]; then
  # Check if this is a git repo
  if [ -d ".git" ]; then
    echo "Initializing Beads for this project..."
    bd init
  fi
fi
```

Configure in `.claude/settings.json`:
```json
{
  "hooks": {
    "SessionStart": {
      "command": "~/.claude/hooks/session-start.sh"
    }
  }
}
```

**Result:**
- Every time you start Claude Code in a project
- If it's a git repo and no `.beads/`
- Auto-initialize

## Strategy 3: Lazy Git-Like Behavior

Make BeadsHub MCP work WITHOUT `.beads/` directories locally:

```typescript
class BeadsHubMCP {
  async todo_create(params) {
    // Don't require .beads/ at all!
    // Just track in memory and sync to cloud

    const source = this.identifySource();

    // Create directly in cloud
    await this.cloudAPI.createIssue({
      ...params,
      source_id: source.id,
      source_name: source.name
    });

    // Optionally: create in local .beads/ for offline access
    if (this.config.createLocalBeads) {
      const beadsDir = await this.findOrCreateBeadsDir();
      execSync(`cd ${beadsDir} && bd create "${params.title}"`);
    }
  }

  identifySource() {
    const cwd = process.cwd();

    // Generate source ID from current context
    if (this.isGitRepo(cwd)) {
      // Use git remote as source ID
      const remote = execSync('git remote get-url origin', { cwd, encoding: 'utf8' }).trim();
      return {
        id: this.hashString(remote),
        name: path.basename(cwd),
        type: 'git_repo',
        path: cwd
      };
    }

    // Use directory path as source
    return {
      id: this.hashString(cwd),
      name: path.basename(cwd),
      type: 'directory',
      path: cwd
    };
  }
}
```

**Result:**
- No `.beads/` directories needed locally
- Issues stored in cloud immediately
- Optional local `.beads/` for offline use
- Source identified by git remote or directory path

## Strategy 4: Bulk Init Script

One-time script to initialize `.beads/` in all existing projects:

```bash
#!/bin/bash
# beadshub-bulk-init.sh

echo "Finding all git repositories..."

# Find all git repos in common locations
find ~/projects ~/work ~/Documents -name ".git" -type d 2>/dev/null | while read gitdir; do
  projectdir=$(dirname "$gitdir")

  # Skip if already has .beads
  if [ -d "$projectdir/.beads" ]; then
    echo "✓ $projectdir (already initialized)"
    continue
  fi

  echo "Initializing $projectdir..."
  cd "$projectdir"
  bd init

  echo "✓ $projectdir"
done

echo ""
echo "Done! Initialized Beads in all git repositories."
```

Run once:
```bash
chmod +x beadshub-bulk-init.sh
./beadshub-bulk-init.sh
```

**Result:**
- All your existing 30+ projects get `.beads/` in one go
- Never think about it again

## Strategy 5: BeadsHub CLI Wrapper

Replace `bd` with `bh` (BeadsHub CLI) that auto-inits:

```bash
#!/bin/bash
# bh (BeadsHub wrapper)

# Auto-init if needed
if [ ! -d ".beads" ]; then
  # Check if in a project
  if [ -d ".git" ] || [ -f "package.json" ] || [ -f "Cargo.toml" ]; then
    echo "Auto-initializing Beads..."
    bd init
  fi
fi

# Forward to bd
bd "$@"
```

Usage:
```bash
# Instead of:
bd create "Fix bug"

# Use:
bh create "Fix bug"  # Auto-inits if needed
```

Or alias it:
```bash
alias bd='bh'  # Transparent replacement
```

## Strategy 6: Global .beads/ (Not Recommended)

One global `.beads/` for everything:

```bash
mkdir -p ~/.beadshub/global
cd ~/.beadshub/global
bd init

# MCP always uses this
```

**Pros:**
- Never need to init
- One place for everything

**Cons:**
- ❌ Loses project context
- ❌ All issues in one source
- ❌ Can't use Beads dependency features well
- ❌ Git sync doesn't make sense

## Recommended Approach: Hybrid

Combine strategies for best UX:

### For Coding Projects (with git):

**Auto-init on first use:**

```typescript
async findOrCreateBeadsDir() {
  // 1. Look for existing .beads (current or parent dirs)
  const existing = this.findExistingBeads();
  if (existing) return existing;

  // 2. If in a git repo, auto-init here
  if (this.isGitRepo(process.cwd())) {
    const root = this.findGitRoot();
    execSync(`cd ${root} && bd init`);
    console.log(`✓ Initialized .beads/ in ${root}`);
    return root;
  }

  // 3. If in a project (has package.json etc), auto-init here
  const projectRoot = this.findProjectRoot();
  if (projectRoot) {
    execSync(`cd ${projectRoot} && bd init`);
    console.log(`✓ Initialized .beads/ in ${projectRoot}`);
    return projectRoot;
  }

  // 4. Fall back to personal directory
  return this.getPersonalBeadsDir();
}

getPersonalBeadsDir() {
  const dir = path.join(os.homedir(), '.beadshub', 'personal');
  if (!fs.existsSync(`${dir}/.beads`)) {
    fs.mkdirSync(dir, { recursive: true });
    execSync(`cd ${dir} && bd init`);
    console.log(`✓ Initialized personal .beads/ in ${dir}`);
  }
  return dir;
}
```

### For Random Sessions:

**Use personal directory automatically:**

```typescript
// When agent creates todo in random location
if (inRandomLocation) {
  // Don't pollute random dirs with .beads/
  // Use personal directory instead
  const personalDir = '~/.beadshub/personal';
  execSync(`cd ${personalDir} && bd create "${title}"`);
}
```

## User Experience Examples

### Example 1: First Time in New Project

```bash
cd ~/projects/new-project
# (no .beads/ yet)

# User talks to Claude Code
User: "Add todo to implement auth"

# MCP server:
# - Detects: in directory new-project
# - Checks: is this a git repo? Yes (.git exists)
# - Action: Auto-run `bd init`
# - Output: "✓ Initialized .beads/ in new-project"
# - Then: Create issue "Implement auth"

Claude: "✓ Created todo: Implement auth (in new-project)"
```

**Result:** User never ran `bd init` manually!

### Example 2: Already Has .beads/

```bash
cd ~/projects/existing-project
# (already has .beads/)

User: "Add todo to fix bug"

# MCP server:
# - Finds: .beads/ already exists
# - Action: Just create issue

Claude: "✓ Created todo: Fix bug (in existing-project)"
```

**Result:** Just works

### Example 3: Random Location

```bash
cd ~/Downloads/temp
# (random location, not a project)

User: "Add todo to call John tomorrow"

# MCP server:
# - Detects: not in a project
# - Action: Use personal directory (~/.beadshub/personal)

Claude: "✓ Created todo: Call John tomorrow (in personal)"
```

**Result:** Todo still created, in sensible location

### Example 4: Subdirectory of Project

```bash
cd ~/projects/myapp/src/components
# (in subdirectory)

User: "Add todo to refactor this component"

# MCP server:
# - Searches up: finds .beads/ in ~/projects/myapp
# - Action: Create issue there

Claude: "✓ Created todo: Refactor this component (in myapp)"
```

**Result:** Git-like behavior, finds project root

## Configuration

Let users control auto-init behavior:

```json
// ~/.beadshub/config.json
{
  "auto_init": {
    "enabled": true,
    "git_repos_only": true,        // Only auto-init in git repos
    "ask_first": false,             // Or ask user before init
    "personal_fallback": true,      // Use personal dir for non-projects
    "search_parent_dirs": true      // Search up like git does
  },

  "sources": {
    "personal_dir": "~/.beadshub/personal",
    "auto_discover": true,
    "ignore_patterns": [
      "**/node_modules/**",
      "**/venv/**"
    ]
  }
}
```

If user wants control:
```json
{
  "auto_init": {
    "enabled": true,
    "ask_first": true  // Prompt before creating .beads/
  }
}
```

Then:
```bash
User: "Add todo"

Claude: "This directory doesn't have .beads/ yet.
Initialize Beads here? [Y/n]"

User: "y"

Claude: "✓ Initialized .beads/
✓ Created todo: ..."
```

## What bd Already Supports

Checked the Beads repo - `bd` already has smart init:

```bash
# bd automatically creates .beads/ if needed
bd create "Issue title"
# If no .beads/, it will:
# 1. Prompt: "Initialize Beads here? [Y/n]"
# 2. Run `bd init` if yes
# 3. Then create the issue
```

So bd ALREADY does auto-init with confirmation!

## Updated Recommendation

Since `bd` already prompts for init, the MCP server can just:

```typescript
async todo_create(params) {
  const beadsDir = await this.findBeadsDir();

  // bd will handle init prompt if needed
  // We can auto-answer "yes" via stdin
  const result = execSync(
    `cd ${beadsDir} && echo "y" | bd create "${params.title}" --json`,
    { encoding: 'utf8' }
  );

  return JSON.parse(result);
}
```

Or configure bd to not prompt:
```bash
# Set environment variable
export BD_AUTO_INIT=1

# Now bd auto-inits without asking
bd create "Issue"
```

## Summary

**You don't need to manually create `.beads/` every time!**

**Options (pick one or combine):**

1. **MCP auto-init** - MCP server detects project root, runs `bd init` automatically
2. **bd's native auto-init** - bd already prompts to init, MCP can auto-answer "yes"
3. **Bulk init script** - One-time initialize all 30+ existing projects
4. **Session hook** - Auto-init when Claude Code starts in a project
5. **Personal fallback** - For random sessions, use `~/.beadshub/personal`

**Recommended config:**
```bash
# Environment variable
export BD_AUTO_INIT=1  # bd auto-inits without prompting

# MCP server config
{
  "auto_init": true,
  "git_repos_only": true,
  "personal_fallback": "~/.beadshub/personal"
}
```

**Result:**
- ✅ First todo in a git repo? Auto-creates `.beads/`
- ✅ Subdirectory? Finds parent `.beads/` (like git)
- ✅ Random location? Uses personal directory
- ✅ Zero manual `bd init` commands needed!
