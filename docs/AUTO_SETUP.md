# auto setup

how .beads/ directories get created and registered automatically

## auto-init: creating .beads/ directories

### mcp auto-init (recommended)

mcp server automatically initializes .beads/ when needed:

```typescript
async findOrCreateBeadsDir() {
  const cwd = process.cwd();

  // check current and parent directories
  const existing = this.findExistingBeads(cwd);
  if (existing) return existing;

  // if in git repo, auto-init here
  if (this.isGitRepo(cwd)) {
    const root = this.findGitRoot(cwd);
    execSync(`cd ${root} && bd init`);
    return root;
  }

  // if in project (has package.json etc), auto-init here
  const projectRoot = this.findProjectRoot(cwd);
  if (projectRoot) {
    execSync(`cd ${projectRoot} && bd init`);
    return projectRoot;
  }

  // fall back to personal directory
  const personal = path.join(os.homedir(), '.beadster', 'personal');
  if (!fs.existsSync(`${personal}/.beads`)) {
    fs.mkdirSync(personal, { recursive: true });
    execSync(`cd ${personal} && bd init`);
  }
  return personal;
}
```

result:
- agent creates first todo → mcp auto-creates .beads/ in right place
- no manual bd init needed
- smart detection: git root > project root > personal

### bulk init for existing projects

one-time script to initialize all projects:

```bash
#!/bin/bash
find ~/projects ~/work -name ".git" -type d 2>/dev/null | while read gitdir; do
  projectdir=$(dirname "$gitdir")

  if [ -d "$projectdir/.beads" ]; then
    echo "✓ $projectdir (already initialized)"
    continue
  fi

  echo "initializing $projectdir..."
  cd "$projectdir" && bd init
done
```

## auto-registration: tracking .beads/ directories

### symlinks registry approach

each .beads/ directory registers itself:

```
~/.beadster/sources/
├── main-app -> ~/projects/main-app/.beads
├── side-project -> ~/projects/side-project/.beads
└── inbox -> ~/.beadster/inbox/.beads
```

when bd init runs:

```bash
cd ~/projects/new-project
bd init

# post-init hook:
beadster register .

# creates symlink:
ln -s ~/projects/new-project/.beads ~/.beadster/sources/new-project
```

### sync daemon discovery

```typescript
class SyncDaemon {
  async discoverSources() {
    const sourcesDir = path.join(os.homedir(), '.beadster', 'sources');
    const entries = fs.readdirSync(sourcesDir);

    const sources = [];
    for (const entry of entries) {
      const linkPath = path.join(sourcesDir, entry);
      if (fs.lstatSync(linkPath).isSymbolicLink()) {
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
}
```

instant discovery - just list symlinks, no scanning

### bd wrapper for auto-registration

```bash
#!/bin/bash
# ~/.local/bin/bd

if [ "$1" = "init" ]; then
  /usr/local/bin/bd "$@"
  beadster register .
else
  /usr/local/bin/bd "$@"
fi
```

## registration metadata

each .beads/ has registration info:

```
~/projects/main-app/.beads/
├── issues/           # beads JSONL files (source of truth)
├── beads.db          # beads cache + beadster extension tables
└── beadster.json     # registration metadata
```

beadster.json:

```json
{
  "source_id": "main-app-abc123",
  "registered": true,
  "sync_enabled": true,
  "registry_path": "~/.beadster/sources/main-app",
  "cloud_source_id": "src_xyz789",
  "last_sync": 1729180234
}
```

## cli commands

```bash
# register current directory
beadster register .

# register specific directory
beadster register ~/projects/my-app

# unregister
beadster unregister my-app

# list registered sources
beadster sources

# discover and register all
beadster discover
```

## user experience

first time in new project:

```
cd ~/projects/new-project
# no .beads/ yet

User: "add todo to implement auth"

# mcp auto-inits:
# ✓ initialized .beads/ in new-project
# ✓ registered with sync daemon
# ✓ created todo: implement auth
```

subdirectory of project:

```
cd ~/projects/myapp/src/components

User: "add todo to refactor this"

# mcp finds .beads/ in parent:
# ✓ found .beads/ in ~/projects/myapp
# ✓ created todo there
```

random location:

```
cd ~/Downloads/temp

User: "add todo to call john"

# mcp uses personal directory:
# ✓ created todo in personal
```

## configuration

```json
// ~/.beadster/config.json
{
  "auto_init": {
    "enabled": true,
    "git_repos_only": true,
    "personal_fallback": "~/.beadster/personal"
  },
  "sources": {
    "auto_discover": true,
    "ignore_patterns": ["**/node_modules/**", "**/venv/**"]
  }
}
```

## summary

no manual bd init or registration needed:

- first todo in git repo? auto-creates .beads/
- subdirectory? finds parent .beads/ like git
- random location? uses personal directory
- auto-registers with sync daemon via symlinks
- instant discovery, no scanning
