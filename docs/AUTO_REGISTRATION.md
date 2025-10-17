# Auto-Registration of .beads/ Directories

## Problem

You have 30+ projects scattered everywhere. Instead of sync daemon scanning your entire home directory, what if each .beads/ directory auto-registers itself with BeadsHub?

## Solution: Self-Registration via Central Registry

Each .beads/ directory registers itself in a central location when created.

### Approach 1: Symlinks Registry

```
~/.beadshub/sources/
├── main-app -> ~/projects/main-app/.beads
├── side-project -> ~/projects/side-project/.beads
├── company-site -> ~/work/company/.beads
├── ngo-website -> ~/Documents/ngo/.beads
└── inbox -> ~/.beadshub/inbox/.beads
```

**How it works:**

```bash
# When bd init runs (or BeadsHub wrapper)
cd ~/projects/new-project
bd init

# Post-init hook automatically runs:
beadshub register .

# This creates:
ln -s ~/projects/new-project/.beads ~/.beadshub/sources/new-project
```

**Benefits:**
- ✅ Instant discovery - just list ~/.beadshub/sources/
- ✅ No scanning needed
- ✅ Works with any file watcher
- ✅ Can manually add/remove symlinks
- ✅ Human-readable

**Sync daemon:**
```typescript
class SyncDaemon {
  async discoverSources() {
    const sourcesDir = path.join(os.homedir(), '.beadshub', 'sources');

    // Just read symlinks - instant!
    const entries = fs.readdirSync(sourcesDir);

    const sources = [];
    for (const entry of entries) {
      const linkPath = path.join(sourcesDir, entry);
      const stats = fs.lstatSync(linkPath);

      if (stats.isSymbolicLink()) {
        const target = fs.readlinkSync(linkPath);
        const realPath = path.resolve(path.dirname(target));

        sources.push({
          name: entry,
          beadsPath: target,
          projectPath: realPath
        });
      }
    }

    return sources;
  }

  async watchAllSources() {
    const sources = await this.discoverSources();

    for (const source of sources) {
      // Watch the target directory (the actual .beads/)
      this.watchSource(source);
    }
  }
}
```

**Auto-registration in bd wrapper:**

```bash
#!/bin/bash
# ~/.local/bin/bd (wrapper around real bd)

# If running init, register after
if [ "$1" = "init" ]; then
  # Run real bd
  /usr/local/bin/bd "$@"

  # Register this .beads/ directory
  beadshub register .
else
  # Just forward to real bd
  /usr/local/bin/bd "$@"
fi
```

Or install as git hook:

```bash
# .beads/hooks/post-init
#!/bin/bash
beadshub register .
```

### Approach 2: Registry File (JSON)

```
~/.beadshub/registry.json
```

```json
{
  "sources": [
    {
      "id": "main-app",
      "name": "main-app",
      "path": "/Users/anton/projects/main-app",
      "beads_path": "/Users/anton/projects/main-app/.beads",
      "registered_at": 1729180234,
      "type": "local",
      "auto_discovered": false
    },
    {
      "id": "side-project",
      "name": "side-project",
      "path": "/Users/anton/projects/side-project",
      "beads_path": "/Users/anton/projects/side-project/.beads",
      "registered_at": 1729180235,
      "type": "local",
      "auto_discovered": true
    }
  ]
}
```

**Registration command:**

```bash
cd ~/projects/new-project
bd init

# Register
beadshub register .
# or
beadshub register ~/projects/new-project
```

**Benefits:**
- ✅ More metadata (registered_at, type, etc.)
- ✅ Can track disabled sources
- ✅ Easy to read/edit
- ✅ Works on all platforms (Windows doesn't have symlinks by default)

**Drawbacks:**
- ❌ Need to keep JSON in sync with reality
- ❌ Dead entries if directory deleted

### Approach 3: Hybrid (Symlinks + Metadata)

Best of both worlds:

```
~/.beadshub/sources/
├── main-app -> ~/projects/main-app/.beads
├── side-project -> ~/projects/side-project/.beads
└── .registry.json
```

**.registry.json:**
```json
{
  "main-app": {
    "registered_at": 1729180234,
    "type": "local",
    "tags": ["work", "typescript"],
    "enabled": true
  },
  "side-project": {
    "registered_at": 1729180235,
    "type": "local",
    "tags": ["personal", "rust"],
    "enabled": true
  }
}
```

**Benefits:**
- ✅ Symlinks for discovery (fast, reliable)
- ✅ JSON for metadata (tags, settings)
- ✅ Human can add symlink manually
- ✅ Can disable without removing symlink

### Approach 4: Each .beads/ Has Metadata File

Every .beads/ directory has a registration file:

```
~/projects/main-app/.beads/
├── issues/
├── beads.db
└── beadshub.json    # ← Registration metadata
```

**beadshub.json:**
```json
{
  "source_id": "main-app-abc123",
  "registered": true,
  "sync_enabled": true,
  "registry_path": "~/.beadshub/sources/main-app",
  "cloud_source_id": "src_xyz789",
  "last_sync": 1729180234,
  "tags": ["work", "typescript"]
}
```

**On bd init:**
```bash
cd ~/projects/new-project
bd init

# Beadshub extension runs (post-init hook)
beadshub init-hook

# Creates:
# 1. .beads/beadshub.json
# 2. Symlink in ~/.beadshub/sources/
# 3. Registers with cloud
```

**Benefits:**
- ✅ Self-contained - .beads/ directory knows about registration
- ✅ Can check: "Is this registered?" from within directory
- ✅ Metadata travels with .beads/ (if you copy directory)
- ✅ Can deregister by deleting beadshub.json

## Registration Flow

### Automatic Registration (Recommended)

**Option A: Wrapper around bd**

Install BeadsHub, it installs bd wrapper:

```bash
# Install BeadsHub
brew install beadshub

# This installs:
# - ~/.beadshub/ infrastructure
# - Sync daemon
# - bd wrapper at ~/.local/bin/bd (higher priority in PATH)
```

Wrapper:

```bash
#!/bin/bash
# ~/.local/bin/bd

BD_BIN="/usr/local/bin/bd"  # Real bd

case "$1" in
  init)
    # Run real bd init
    $BD_BIN "$@"

    # Auto-register
    if [ $? -eq 0 ]; then
      beadshub register . --auto
    fi
    ;;

  *)
    # Forward everything else
    $BD_BIN "$@"
    ;;
esac
```

**Result:** Every time you run `bd init`, it auto-registers.

**Option B: bd Plugin/Extension**

Beads supports extensions (check EXTENDING.md). Could add:

```bash
# .beads/config.toml

[extensions]
beadshub = true

[beadshub]
auto_register = true
sync_daemon = true
```

When bd init runs with extension enabled:
1. Creates .beads/
2. Runs beadshub extension hook
3. Extension registers with BeadsHub

### Manual Registration

```bash
# Register current directory
beadshub register .

# Register specific directory
beadshub register ~/projects/old-project

# Register with custom name
beadshub register . --name="company-website"

# Register with tags
beadshub register . --tags="work,typescript,api"

# Bulk register (one-time setup)
beadshub discover
# Scans ~/projects, ~/work, etc. for .beads/
# Shows list, asks to register all
```

### Cloud Registration

When source registers locally, also register in cloud:

```typescript
async function registerSource(localPath: string) {
  const projectPath = path.dirname(localPath);  // Remove /.beads
  const name = path.basename(projectPath);

  // 1. Create symlink
  const symlinkPath = path.join(
    os.homedir(),
    '.beadshub',
    'sources',
    name
  );

  fs.symlinkSync(localPath, symlinkPath);

  // 2. Create metadata
  const metadata = {
    registered_at: Date.now(),
    type: 'local',
    path: projectPath,
    beads_path: localPath
  };

  const registryPath = path.join(
    os.homedir(),
    '.beadshub',
    'sources',
    '.registry.json'
  );

  const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  registry[name] = metadata;
  fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2));

  // 3. Create .beads/beadshub.json
  fs.writeFileSync(
    path.join(localPath, 'beadshub.json'),
    JSON.stringify({
      source_id: `${name}-${Date.now()}`,
      registered: true,
      sync_enabled: true,
      registry_path: symlinkPath
    }, null, 2)
  );

  // 4. Register with cloud
  await fetch('https://api.beadshub.com/api/sources', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${getApiKey()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      name,
      type: 'local',
      path: projectPath,
      machine_id: getMachineId()
    })
  });

  console.log(`✓ Registered: ${name}`);
  console.log(`  Path: ${projectPath}`);
  console.log(`  Registry: ${symlinkPath}`);
}
```

## Discovery Without Registration

Even if user doesn't register, BeadsHub can still discover:

```bash
# First time setup
beadshub setup

> Would you like to scan for existing .beads/ directories?
> [Y/n]

# Scans common locations:
# - ~/projects
# - ~/work
# - ~/Documents
# - ~/Desktop
# - Custom: ask user for additional paths

Found 32 .beads/ directories:

1. ~/projects/main-app/.beads (23 issues)
2. ~/projects/side-project/.beads (5 issues)
...
32. ~/work/client-site/.beads (8 issues)

Register all? [Y/n] y

Registering...
✓ main-app
✓ side-project
...
✓ client-site

Done! 32 sources registered.
Start sync daemon? [Y/n]
```

After this one-time discovery, new .beads/ directories use auto-registration.

## Unregistration

```bash
# Unregister source
beadshub unregister main-app

# This:
# 1. Removes symlink
# 2. Removes from registry.json
# 3. Marks as deleted in cloud (keeps history)
# 4. Stops watching

# Or from within directory
cd ~/projects/main-app
beadshub unregister .
```

**Soft delete in cloud:**
```sql
CREATE TABLE sources (
  ...
  deleted_at INTEGER,
  deleted_reason TEXT
);

-- Keep history
UPDATE sources
SET deleted_at = ?, deleted_reason = 'user_unregistered'
WHERE id = ?;

-- Issues stay but marked
UPDATE issues
SET source_deleted = 1
WHERE source_id = ?;
```

## Watching for New Registrations

Sync daemon watches registry directory:

```typescript
class SyncDaemon {
  async start() {
    // Watch registry directory for new symlinks
    const sourcesDir = path.join(os.homedir(), '.beadshub', 'sources');

    fs.watch(sourcesDir, (eventType, filename) => {
      if (eventType === 'rename') {
        // New symlink added or removed
        this.handleSourceChange(filename);
      }
    });

    // Initial load
    await this.loadAllSources();
  }

  async handleSourceChange(name: string) {
    const symlinkPath = path.join(
      os.homedir(),
      '.beadshub',
      'sources',
      name
    );

    if (fs.existsSync(symlinkPath)) {
      // New source added
      console.log(`New source detected: ${name}`);
      await this.addSourceToSync(name);
    } else {
      // Source removed
      console.log(`Source removed: ${name}`);
      await this.removeSourceFromSync(name);
    }
  }
}
```

## Integration with MCP

MCP server uses registry:

```typescript
class BeadsHubMCP {
  async findBeadsDir() {
    const cwd = process.cwd();

    // 1. Check if current directory is registered
    const registered = await this.findRegisteredSource(cwd);
    if (registered) return registered;

    // 2. Check parent directories
    let dir = cwd;
    while (dir !== '/' && dir.length > 1) {
      if (fs.existsSync(`${dir}/.beads`)) {
        // Found .beads/, check if registered
        if (!this.isRegistered(dir)) {
          // Auto-register
          await this.registerSource(dir);
        }
        return dir;
      }
      dir = path.dirname(dir);
    }

    // 3. Check if in git repo - auto-init and register
    if (this.isGitRepo(cwd)) {
      const root = this.findGitRoot();
      execSync(`cd ${root} && bd init`);
      await this.registerSource(root);
      return root;
    }

    // 4. Use inbox
    return this.getInboxPath();
  }

  async findRegisteredSource(cwd: string): Promise<string | null> {
    const sourcesDir = path.join(os.homedir(), '.beadshub', 'sources');
    const entries = fs.readdirSync(sourcesDir);

    for (const entry of entries) {
      const symlinkPath = path.join(sourcesDir, entry);
      if (!fs.lstatSync(symlinkPath).isSymbolicLink()) continue;

      const target = fs.readlinkSync(symlinkPath);
      const projectPath = path.resolve(path.dirname(target));

      // Check if cwd is in this project
      if (cwd.startsWith(projectPath)) {
        return projectPath;
      }
    }

    return null;
  }

  isRegistered(projectPath: string): boolean {
    const beadsPath = path.join(projectPath, '.beads');
    const beadshubJson = path.join(beadsPath, 'beadshub.json');

    if (!fs.existsSync(beadshubJson)) return false;

    const config = JSON.parse(fs.readFileSync(beadshubJson, 'utf8'));
    return config.registered === true;
  }

  async registerSource(projectPath: string) {
    const beadsPath = path.join(projectPath, '.beads');

    // Use CLI tool
    execSync(`beadshub register ${beadsPath}`, { stdio: 'inherit' });
  }
}
```

## Recommended Setup

**Best approach: Hybrid (symlinks + metadata)**

### Directory structure:

```
~/.beadshub/
├── sources/                    # Registry directory
│   ├── main-app -> ~/projects/main-app/.beads
│   ├── side-project -> ~/projects/side-project/.beads
│   ├── inbox -> ~/.beadshub/inbox/.beads
│   └── .registry.json         # Metadata
├── inbox/.beads/              # Default inbox
├── config.json                # User config
└── sync.log                   # Sync daemon log
```

### Each .beads/ has:

```
~/projects/main-app/.beads/
├── issues/
├── beads.db
└── beadshub.json              # Registration info
```

### Registration flow:

1. User runs `bd init` or `beadshub register .`
2. Creates symlink in `~/.beadshub/sources/`
3. Creates `.beads/beadshub.json`
4. Updates `.registry.json`
5. Registers with cloud API
6. Sync daemon picks it up automatically

### Benefits:

- ✅ Fast discovery (just list symlinks)
- ✅ Rich metadata (registry.json + beadshub.json)
- ✅ Self-contained (.beads/ knows it's registered)
- ✅ Survives directory moves (can detect and fix)
- ✅ Manual control (can add/remove symlinks)
- ✅ Works with file watchers
- ✅ Cross-platform (with fallback to JSON-only on Windows)

## CLI Commands

```bash
# Register
beadshub register .
beadshub register ~/projects/my-app
beadshub register . --name="custom-name" --tags="work,api"

# Unregister
beadshub unregister my-app
beadshub unregister .

# List registered
beadshub sources
# Output:
# main-app      ~/projects/main-app        23 issues    ✓ syncing
# side-project  ~/projects/side-project    5 issues     ✓ syncing
# inbox         ~/.beadshub/inbox          12 issues    ✓ syncing

# Discover and register
beadshub discover
beadshub discover --path ~/work
beadshub discover --register-all

# Check registration status
cd ~/projects/main-app
beadshub status
# Output:
# Source: main-app
# Registered: Yes
# Registry: ~/.beadshub/sources/main-app
# Syncing: Yes
# Last sync: 2 minutes ago
# Issues: 23 (12 open, 11 closed)

# Re-register (if moved or broken)
beadshub reregister .
```

## Summary

**Yes, auto-registration via symlinks is totally doable and actually elegant!**

**Key insight:** Instead of scanning entire filesystem, each .beads/ directory registers itself in a central location (`~/.beadshub/sources/`) using symlinks.

**Benefits:**
- Instant discovery (no scanning)
- Explicit registration (you control what syncs)
- Clean registry (easy to see what's registered)
- Works with file watchers
- Can manually add/remove

**Recommended approach:**
- Symlinks for discovery
- JSON for metadata
- Auto-register on `bd init` via wrapper
- One-time bulk discovery for existing projects
- MCP auto-registers when creating .beads/

## Sandboxed macOS App

**Challenge:** Mac App Store apps are sandboxed - can't freely access file system or create symlinks outside container.

### Solution: Managed Container + Explicit Access

```
~/Library/Containers/com.beadshub.BeadsHub/Data/
└── .beadshub/
    ├── inbox/.beads/              # Always accessible
    ├── sources.json               # Registry (no symlinks)
    └── config.json
```

**sources.json:**
```json
{
  "sources": [
    {
      "id": "inbox",
      "name": "inbox",
      "path": "~/Library/Containers/com.beadshub.BeadsHub/Data/.beadshub/inbox",
      "type": "container",
      "access": "granted"
    },
    {
      "id": "main-app",
      "name": "main-app",
      "path": "/Users/anton/projects/main-app",
      "type": "external",
      "access": "granted",
      "bookmark": "<security-scoped-bookmark>"
    }
  ]
}
```

### How Registration Works

**User opens BeadsHub Mac app:**

```
BeadsHub App

[Inbox] (12 issues)
└─ Always available, inside app container

[+] Add Project

> You clicked Add Project

Two options:

1. [Create Cloud-Only Project]
   → Virtual source, no local files

2. [Link Existing Folder]
   → Opens file picker
   → You choose: ~/projects/main-app
   → App requests security-scoped bookmark
   → macOS shows: "BeadsHub wants to access main-app folder"
   → You click Allow
   → App saves bookmark, can access forever
```

**After granting access:**

```typescript
// In Mac app
class SourceManager {
  async addExternalSource(folderURL: URL) {
    // Request security-scoped access
    const bookmark = try folderURL.bookmarkData(
      options: .withSecurityScope
    );

    // Check if has .beads/
    const beadsPath = folderURL.appendingPathComponent('.beads');

    if (!fileManager.fileExists(atPath: beadsPath.path)) {
      // Ask user
      Alert: "This folder doesn't have .beads/. Initialize?"
      → Yes: Run bd init (via embedded bd binary)
      → No: Cancel
    }

    // Save to registry
    const source = {
      id: UUID(),
      name: folderURL.lastPathComponent,
      path: folderURL.path,
      type: 'external',
      access: 'granted',
      bookmark: bookmark.base64EncodedString(),
      added_at: Date.now()
    };

    this.sources.append(source);
    this.saveSources();

    // Start syncing
    this.syncDaemon.watch(source);
  }

  async accessExternalSource(source: Source) {
    // Restore access from bookmark
    const bookmarkData = Data(base64Encoded: source.bookmark);
    var isStale = false;

    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      bookmarkDataIsStale: &isStale
    );

    if (isStale) {
      // Re-request access
      url = this.repromptForAccess(source);
    }

    return url;
  }
}
```

### User Experience

**First launch:**

```
Welcome to BeadsHub!

Your inbox is ready.
Tasks you create will go here by default.

Want to link existing projects?

[Scan for Projects]  [Add Manually]  [Skip for Now]
```

**If user clicks "Scan for Projects":**

```
Choose folders to scan:
☑ ~/projects
☑ ~/work
☐ ~/Documents
☐ ~/Desktop

[Scan]

→ Opens folder picker for each selected location
→ User grants access to ~/projects
→ User grants access to ~/work
→ App scans for .beads/ directories
→ Found:
   • ~/projects/main-app/.beads
   • ~/projects/side-project/.beads
   • ~/work/company-site/.beads

Add these projects?
☑ main-app (23 issues)
☑ side-project (5 issues)
☑ company-site (12 issues)

[Add Selected]

→ Saves bookmarks
→ Starts syncing
→ Done!
```

**Add project manually:**

```
[Add Project]

1. [Create New]
   Name: ____________
   Type: [Cloud-Only ▼] [Local Folder ▼]

2. [Link Existing]
   → Opens file picker
   → Choose folder
   → Detects .beads/ or offers to create
```

### No brew install Needed!

**BeadsHub Mac app bundles everything:**

```
BeadsHub.app/
├── Contents/
│   ├── MacOS/
│   │   ├── BeadsHub              # Main app binary
│   │   ├── bd                    # Embedded bd CLI
│   │   └── beadshub-sync         # Sync daemon
│   └── Resources/
│       └── ...
```

**App manages everything internally:**
- No CLI needed
- No Terminal usage
- All visual
- Handles file access permissions via macOS APIs

### Folder Access Patterns

**Pattern 1: Inbox (Always Works)**

```swift
// Inside app container - always accessible
let inbox = containerURL
  .appendingPathComponent(".beadshub")
  .appendingPathComponent("inbox")
  .appendingPathComponent(".beads")

// No permission needed
bd.create(in: inbox, title: "Task")
```

**Pattern 2: External Project (Requires Permission)**

```swift
// User granted access via file picker
let source = sources.first(where: { $0.id == "main-app" })!

// Restore access from bookmark
let projectURL = try URL(
  resolvingBookmarkData: Data(base64Encoded: source.bookmark)!
)

// Access granted - can read/write
bd.create(in: projectURL.appendingPathComponent(".beads"), title: "Task")
```

**Pattern 3: Cloud-Only (No Local Files)**

```swift
// No file access needed
api.createIssue(source: "company-admin", title: "Task")
```

## iOS App

**Even more restricted:** Can only access:
1. App's own container
2. User's iCloud Drive (if enabled)
3. Files explicitly picked by user

### Solution: Cloud-First with Optional Local Cache

```
iOS App Container/
└── Library/
    └── Caches/
        └── beadshub/
            └── cache.db           # Local cache of cloud data
```

**Everything is cloud:**

```swift
// iOS app - all operations via cloud API
class BeadsHubService {
  func createIssue(title: String, source: String?) async {
    // Direct to cloud
    try await api.post("/api/issues", body: [
      "title": title,
      "source_id": source ?? "inbox"
    ])

    // Update local cache
    cache.insert(issue)
  }

  func listIssues(source: String?) async -> [Issue] {
    // Try cache first
    if let cached = cache.getIssues(source: source) {
      // Refresh in background
      Task { await refreshFromCloud(source: source) }
      return cached
    }

    // Fetch from cloud
    let issues = try await api.get("/api/issues", params: [
      "source": source
    ])

    // Update cache
    cache.save(issues)

    return issues
  }
}
```

### iOS User Experience

**First launch:**

```
┌─────────────────────────────┐
│ Welcome to BeadsHub         │
├─────────────────────────────┤
│                              │
│ Your tasks, everywhere       │
│                              │
│ • View all your Beads issues │
│ • Create new tasks           │
│ • Mark complete              │
│ • Works offline              │
│                              │
│ [Get Started]                │
│                              │
└─────────────────────────────┘
```

**Main screen:**

```
┌─────────────────────────────┐
│ ☰  BeadsHub          [+]    │
├─────────────────────────────┤
│ 🔥 Ready (12)               │
│                              │
│ ⏳ Fix login bug             │
│    main-app                  │
│                              │
│ ⏳ Update landing page       │
│    company-site              │
│                              │
│ ⏳ Review mockups            │
│    inbox                     │
│                              │
├─────────────────────────────┤
│ 📋 All Issues (156)         │
│ ✓ Completed (87)            │
└─────────────────────────────┘
```

**Add task:**

```
┌─────────────────────────────┐
│ ✕  New Task                 │
├─────────────────────────────┤
│ Title:                       │
│ ________________________     │
│                              │
│ Project:                     │
│ [inbox ▼]                    │
│                              │
│ Priority:                    │
│ [○ Low  ◉ Normal  ○ High]   │
│                              │
│                              │
│ [Create]                     │
└─────────────────────────────┘

Projects dropdown:
  inbox (Default)
  main-app
  side-project
  company-site
  ────────────
  + Create New Project
```

**View by project:**

```
┌─────────────────────────────┐
│ ‹  main-app           [⋮]   │
├─────────────────────────────┤
│ 23 issues, 12 open           │
│                              │
│ Ready to Work On (3)         │
│                              │
│ • Fix login bug         🔴   │
│ • Add rate limiting          │
│ • Update tests               │
│                              │
│ Blocked (2)                  │
│                              │
│ • Add OAuth (blocked)   🔒   │
│ • Deploy (blocked)      🔒   │
│                              │
│ All Open (12)                │
│ View All →                   │
└─────────────────────────────┘
```

**No local file access needed!** Everything via cloud.

### Sync Between Mac and iOS

```
Mac App (with local .beads/):
  1. Reads ~/projects/main-app/.beads/
  2. Syncs to cloud
  3. Writes back changes from cloud

iOS App:
  1. Reads from cloud
  2. Caches locally
  3. Writes to cloud

Result:
  - Mac can work offline with local .beads/
  - iOS always needs internet (or uses cache)
  - Both stay in sync via cloud
```

### Creating Projects on iOS

**Option 1: Cloud-only**

```
User taps: [+ Create New Project]

Name: My New Project
Type: Cloud-Only (no local files)

[Create]

→ Creates virtual source in cloud
→ All issues live in cloud
→ Mac app can optionally create local .beads/ later
```

**Option 2: Mac creates, iOS views**

```
On Mac:
  cd ~/projects/new-project
  bd init
  → Mac app auto-syncs

On iOS:
  → Refreshes
  → "new-project" appears in sources list
  → Can view/create issues there
```

## Installation Scenarios

### Scenario 1: Power User (CLI + Mac App)

```bash
# Install CLI tools
brew install beadshub

# This installs:
# - bd CLI (or wrapper)
# - beadshub CLI
# - Sync daemon

# Download Mac app
# Mac app detects CLI is installed
# Uses existing ~/.beadshub/ directory
# Just adds UI on top
```

### Scenario 2: Mac App Only (Sandboxed)

```
1. Download BeadsHub.app from Mac App Store
2. Open app
3. App creates container directory
4. App bundles bd binary internally
5. Everything managed visually
6. No Terminal needed
```

### Scenario 3: iOS Only

```
1. Download BeadsHub from App Store
2. Sign in
3. Pure cloud mode
4. Optional: Sync with Mac later
```

### Scenario 4: All Three

```
1. Install CLI tools (brew)
2. Download Mac app
3. Download iOS app
4. Sign in on all
5. Everything syncs via cloud
```

## File Access Comparison

| | CLI | Mac App (Non-Sandboxed) | Mac App (Sandboxed) | iOS |
|---|-----|-------------------------|---------------------|-----|
| Access ~/projects | ✅ Yes | ✅ Yes | ⚠️ With permission | ❌ No |
| Create symlinks | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| Auto-discover | ✅ Yes | ✅ Yes | ⚠️ With permission | ❌ No |
| Inbox | ✅ ~/.beadshub/inbox | ✅ ~/.beadshub/inbox | ✅ Container | ✅ Cloud |
| Works offline | ✅ Yes | ✅ Yes | ✅ Yes | ⚠️ Cache only |

## Recommended Architecture

### For Sandboxed Mac App

**Don't use symlinks**, use JSON registry:

```json
// ~/Library/Containers/com.beadshub.BeadsHub/Data/sources.json
{
  "sources": [
    {
      "id": "inbox",
      "type": "container",
      "path": "<container>/.beadshub/inbox/.beads",
      "access": "granted"
    },
    {
      "id": "main-app",
      "type": "external",
      "path": "/Users/anton/projects/main-app/.beads",
      "bookmark": "<base64-bookmark>",
      "access": "granted"
    }
  ]
}
```

**Access flow:**

```swift
func accessSource(_ source: Source) -> URL? {
  switch source.type {
  case "container":
    // Always accessible
    return containerURL.appendingPathComponent(source.path)

  case "external":
    // Restore from bookmark
    guard let bookmarkData = Data(base64Encoded: source.bookmark) else {
      return nil
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      bookmarkDataIsStale: &isStale
    ) else {
      return nil
    }

    if isStale {
      // Re-request access
      return repromptAccess(for: source)
    }

    return url

  case "virtual":
    // Cloud-only, no local access
    return nil
  }
}
```

### Best of All Worlds

**Offer both versions:**

1. **CLI + Non-Sandboxed Mac App** (via direct download)
   - Full file system access
   - Auto-discovery
   - Symlink registry
   - Power user features

2. **Sandboxed Mac App** (via Mac App Store)
   - Explicit permissions
   - JSON registry
   - Security-scoped bookmarks
   - Wider distribution

3. **iOS App** (App Store)
   - Cloud-only
   - Local cache
   - Mobile-optimized

Users pick what works for them!

## Summary

**CLI Installation (brew):**
- Full power
- Auto-discovery
- Symlink registry
- No sandboxing

**Sandboxed Mac App:**
- No brew needed
- Bundles bd binary
- Visual setup
- Security-scoped bookmarks for external folders
- JSON registry (no symlinks)
- Inbox always works in container

**iOS App:**
- Cloud-first
- No local files
- Everything via API
- Local cache for offline

**Key insight:** Sandboxed apps can't freely access file system, so:
- Use security-scoped bookmarks for explicit access
- Bundle bd binary in app
- Use JSON registry instead of symlinks
- Inbox lives in app container
- Cloud-first mode for iOS

## How Sandboxed App Discovers .beads/ Directories

**Problem:** Sandboxed app can't freely scan file system to find existing .beads/ directories.

**Solutions:**

### Strategy 1: User-Initiated Scan (Recommended)

User explicitly grants access to folders to scan:

```
[Scan for Projects]

Step 1: Choose folders to scan
→ Opens folder picker
→ User selects ~/projects
→ App gets security-scoped bookmark

Step 2: App scans just that folder
→ Lists subdirectories
→ Checks each for .beads/
→ Shows results

Found 12 projects with .beads/:
☑ main-app (23 issues)
☑ side-project (5 issues)
...

[Add Selected]
```

**Implementation:**

```swift
class Scanner {
  func scanFolder(url: URL) -> [BeadsProject] {
    var projects: [BeadsProject] = []

    // Start accessing security-scoped resource
    guard url.startAccessingSecurityScopedResource() else {
      return []
    }
    defer { url.stopAccessingSecurityScopedResource() }

    // Get contents of folder
    let contents = try? fileManager.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    // Check each subdirectory for .beads/
    for item in contents ?? [] {
      let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

      if isDirectory {
        let beadsPath = item.appendingPathComponent(".beads")
        if fileManager.fileExists(atPath: beadsPath.path) {
          // Found .beads/!
          let project = BeadsProject(
            name: item.lastPathComponent,
            path: item.path,
            beadsPath: beadsPath.path,
            issueCount: countIssues(in: beadsPath)
          )
          projects.append(project)
        }
      }
    }

    return projects
  }

  func countIssues(in beadsPath: URL) -> Int {
    let issuesPath = beadsPath.appendingPathComponent("issues")
    let issues = try? fileManager.contentsOfDirectory(at: issuesPath)
    return issues?.count ?? 0
  }
}
```

### Strategy 2: Manual Add by Project

User knows they have a project with .beads/, adds it manually:

```
[Add Project] → [Link Existing Folder]

→ Opens folder picker
→ User navigates to ~/projects/main-app
→ User clicks "Select"
→ App checks for .beads/
→ If found: "Found 23 issues, add this project?"
→ If not found: "No .beads/ directory. Create one?"
```

### Strategy 3: Drag and Drop

User drags project folders onto app:

```swift
.onDrop(of: [.fileURL]) { providers in
  for provider in providers {
    provider.loadItem(forTypeIdentifier: "public.file-url") { data, error in
      if let data = data as? Data,
         let url = URL(dataRepresentation: data, relativeTo: nil) {

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {

          // Check for .beads/
          let beadsPath = url.appendingPathComponent(".beads")
          if fileManager.fileExists(atPath: beadsPath.path) {
            // Found .beads/!
            self.addProject(url)
          } else {
            // Offer to create
            self.promptToCreateBeads(in: url)
          }
        }
      }
    }
  }
  return true
}
```

**UI:**

```
Drag project folders here to add them
          ┌─────────────────────┐
          │                     │
          │    📁 Drop Here     │
          │                     │
          └─────────────────────┘

or

[Choose Folder] [Scan ~/projects]
```

### Strategy 4: Recent Projects (macOS API)

Access recently opened folders:

```swift
// macOS tracks recently used folders
let recentURLs = NSDocumentController.shared.recentDocumentURLs

for url in recentURLs {
  // Check if any recent folders have .beads/
  let beadsPath = url.appendingPathComponent(".beads")
  if fileManager.fileExists(atPath: beadsPath.path) {
    // Suggest this project
    suggestProject(url)
  }
}
```

**UI:**

```
Recently Used Projects

We noticed these folders you've opened recently:
☐ ~/projects/main-app (has .beads/)
☐ ~/work/company-site (has .beads/)

[Add Selected]
```

### Strategy 5: Integration with Other Apps

Detect if user has VS Code, Cursor, Xcode projects:

```swift
// VS Code workspaces
let vscodeWorkspaces = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/Code/User/workspaceStorage")

// Cursor workspaces
let cursorWorkspaces = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage")

// Xcode derived data
let xcodeProjects = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Developer/Xcode/DerivedData")
```

**But:** Even these require explicit permission in sandboxed app.

Better: Prompt user based on what they have:

```
We noticed you have VS Code installed.
Your projects might be in ~/projects or ~/work.

[Scan ~/projects] [Scan ~/work] [Choose Custom]
```

### Strategy 6: Command Line Helper (If CLI Installed)

If user has `brew install beadshub` CLI:

```swift
// Check if CLI is installed
let cliPath = "/usr/local/bin/beadshub"
if fileManager.fileExists(atPath: cliPath) {
  // CLI can list all sources (has full file access)
  let task = Process()
  task.executableURL = URL(fileURLWithPath: cliPath)
  task.arguments = ["sources", "--json"]

  let pipe = Pipe()
  task.standardOutput = pipe

  try task.run()
  task.waitUntilExit()

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  let sources = try JSONDecoder().decode([Source].self, from: data)

  // Now app knows about all sources from CLI
  // Can request access to each one
}
```

**UI:**

```
CLI Detected!

We found beadshub CLI installed.
It tracks 32 projects.

[Import from CLI]

→ Lists all 32 sources
→ User picks which to add to app
→ App requests permission for each
```

### Strategy 7: Cloud-First Discovery

User adds projects via cloud, Mac app syncs:

```
On beadshub.com:
  User clicks [Connect Repository]
  Enters path: ~/projects/main-app
  Saves

Mac app syncs:
  Downloads source list from cloud
  Sees: main-app at ~/projects/main-app
  Prompts: "Grant access to ~/projects/main-app?"
  User clicks Allow
  App saves bookmark
```

This works because cloud knows about sources from other machines or CLI.

### Strategy 8: MCP Server Registry

If MCP server is running, it might have a registry:

```
~/.beadshub/sources/   (created by MCP or CLI)
```

Sandboxed app can ask user for permission to this one directory:

```
BeadsHub needs access to ~/.beadshub to see your projects.

[Grant Access]

→ User picks ~/.beadshub folder
→ App reads sources/ directory
→ Sees all symlinks or registry.json
→ Requests individual access to each project
```

### Recommended UX Flow

**First launch:**

```
┌─────────────────────────────────────┐
│ Welcome to BeadsHub                 │
├─────────────────────────────────────┤
│                                     │
│ How do you want to get started?     │
│                                     │
│ 1. [Scan for Projects]              │
│    Find .beads/ in your folders     │
│                                     │
│ 2. [Add Manually]                   │
│    Choose specific folders          │
│                                     │
│ 3. [Import from CLI]                │
│    (if you have beadshub CLI)       │
│                                     │
│ 4. [Start Fresh]                    │
│    Use inbox only for now           │
│                                     │
└─────────────────────────────────────┘
```

**Option 1: Scan for Projects**

```
Choose locations to scan:

[Select Folder]  Currently: None selected

Suggestions:
☐ ~/projects
☐ ~/work
☐ ~/Documents
☐ ~/Desktop

[Scan Selected]

→ For each location, opens folder picker
→ User grants access
→ App scans for .beads/
→ Shows results
→ User picks which to add
```

**Option 2: Add Manually**

```
[Choose Folder]

→ Opens folder picker
→ User navigates to ~/projects/main-app
→ Selects folder
→ App checks for .beads/
→ Adds project
```

**Option 3: Import from CLI**

```
Found beadshub CLI with 32 sources

Select sources to add:
☑ main-app         ~/projects/main-app
☑ side-project     ~/projects/side-project
☐ old-project      ~/archive/old-project
...

[Import Selected]

→ For each selected, requests folder access
→ Saves bookmarks
→ Starts syncing
```

**Option 4: Start Fresh**

```
No problem!

Your inbox is ready.
You can add projects later.

[Continue]
```

### Incremental Permission Requests

Don't ask for everything at once:

```
// Bad UX
App: "Give me access to your entire home directory!"

// Good UX
App: "Choose a folder to scan for projects"
User: Picks ~/projects
App: Only scans ~/projects

Later:
App: "Want to add another folder?"
User: Picks ~/work
App: Only scans ~/work
```

### Monitoring for Changes

Once user grants access to a folder, monitor it:

```swift
class FolderMonitor {
  func watchFolder(url: URL) {
    // Use FSEvents or DispatchSource to watch for changes
    let descriptor = open(url.path, O_EVTONLY)

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: .write,
      queue: DispatchQueue.global()
    )

    source.setEventHandler {
      // Folder changed, rescan for new .beads/ directories
      self.rescanFolder(url)
    }

    source.resume()
  }

  func rescanFolder(_ url: URL) {
    let newProjects = scanner.scanFolder(url: url)

    // Check for new projects
    let existing = self.projects.map { $0.path }
    let new = newProjects.filter { !existing.contains($0.path) }

    if !new.isEmpty {
      // Notify user
      NotificationCenter.default.post(
        name: .newProjectsDetected,
        object: new
      )
    }
  }
}
```

**UI notification:**

```
New projects detected!

• ~/projects/new-project (has .beads/)

[Add to BeadsHub]  [Ignore]
```

## Summary: Discovery Strategies

**For sandboxed Mac app, .beads/ discovery requires user action:**

1. **User-initiated scan** (recommended)
   - User picks folders to scan
   - App checks each subfolder for .beads/
   - Shows results, user picks which to add

2. **Manual add**
   - User picks specific folder
   - App checks for .beads/

3. **Drag & drop**
   - User drags folders onto app
   - App checks for .beads/

4. **CLI integration**
   - If CLI installed, import its registry
   - Request access to each source

5. **Cloud sync**
   - Other machines/CLI register sources in cloud
   - Mac app requests local access

6. **Recent files API**
   - Check recently opened folders
   - Suggest if they have .beads/

**Key insight:** Sandboxed app can't auto-discover. User must explicitly grant access to each location. Make this UX smooth and clear.

Want me to detail the security-scoped bookmark implementation or the embedded bd integration?
