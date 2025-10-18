# usage patterns

how to use beadster in different scenarios

## inbox for non-repo tasks

```
~/.beadster/inbox/.beads/
```

this is where all non-repo tasks go:
- company admin work
- ngo projects without repos
- random claude sessions
- planning work

then filter by labels: company, ngo, personal

## source types

beadster handles multiple source types:

### local git repos

```
~/projects/main-app/.beads/
```

- has local .beads/ directory
- synced via sync daemon
- works offline
- git-backed

### inbox (default)

```
~/.beadster/inbox/.beads/
```

- catch-all for non-repo work
- local .beads/ directory
- synced like any other source

### virtual sources (cloud-only)

no local .beads/ needed:

```bash
beadster create-source "ngo-website" --type=virtual
```

- created via web/mobile app
- stored only in cloud
- no local files
- good for mobile-only workflows

## by context

### coding projects

agent detects git repo:

```
cd ~/projects/main-app
User: "add todo to fix auth"

# mcp detects git repo
# uses ~/projects/main-app/.beads/
# creates issue there
```

### random sessions

not in git repo:

```
cd ~/Downloads/temp
User: "add todo to call john"

# mcp uses inbox
# creates in ~/.beadster/inbox/.beads/
```

### subdirectories

like git, finds parent .beads/:

```
cd ~/projects/main-app/src/components
User: "refactor this component"

# searches up directory tree
# finds ~/projects/main-app/.beads/
# creates issue there
```

### mobile only

create source in ios app:

```
1. open beadster ios app
2. tap "new project"
3. name: "planning"
4. type: cloud-only
5. create todos
```

no mac needed, everything in cloud

## by device

### macbook pro (main machine)

- has all local .beads/ directories
- runs sync daemon
- uses bd cli via mcp
- works offline

### iphone

- cloud-only access
- no local .beads/
- all via api
- requires internet

### work laptop

- different set of projects
- separate sync daemon
- same cloud account
- different device_id

all devices sync via cloud

## by client

### claude code

most common:

```
working in vscode → claude code mcp
↓
detects git repo
↓
uses local .beads/
↓
sync daemon pushes to cloud
```

### claude desktop

planning/research:

```
random conversation → claude desktop mcp
↓
not in repo
↓
uses inbox
↓
sync daemon pushes to cloud
```

### mobile app

native ios app:

```
tap create todo → directly to api
↓
stores in cloud
↓
no local .beads/
```

### web ui

browser:

```
visit beadster.com → create issue
↓
directly to api
↓
sync daemon pulls to local .beads/
```

## filtering and views

### view all issues

```
beadster.com

all issues (342)
- show everything
- group by source
- group by session
- group by device
```

### view by source

```
beadster.com/sources/main-app

main-app (23 issues)
- only issues from this project
- show dependency tree
- ready work
```

### view by session

```
beadster.com/sessions

recent sessions:
- claude code - today 2:30 pm (5 issues)
- claude desktop - yesterday (3 issues)
- ios app - oct 15 (2 issues)
```

click session → see all issues from that conversation

### view by device

```
beadster.com/devices

macbook pro: 234 issues
iphone: 45 issues
work laptop: 67 issues
```

### ready work

```
bd ready
# or
beadster.com/ready

shows only issues with no blockers across all sources
```

## workflow patterns

### developer with multiple projects

setup:

```bash
brew install beadster
beadster discover  # finds all git repos
beadster sync start  # watches all
```

daily use:

```
work in any project → agent creates todos via bd
↓
sync daemon syncs to cloud
↓
view all work on beadster.com
↓
check mobile app for overview
```

### solo developer, mobile-heavy

setup:

```
1. install beadster ios app
2. sign in with apple id
3. create cloud-only sources
```

daily use:

```
think of todo → add in ios app
↓
stored in cloud
↓
later: open laptop, sync daemon pulls
↓
agent sees todos in local .beads/
```

### team collaboration

setup:

```
each team member:
- installs sync daemon
- shares same cloud account (future: team accounts)
- syncs same sources
```

daily use:

```
member 1 creates issue → syncs to cloud
↓
member 2's sync daemon pulls
↓
appears in member 2's local .beads/
↓
both see updates in real-time
```

### non-technical user

setup:

```
1. download beadster mac app
2. sign in with apple id
3. use gui only, no cli
```

daily use:

```
open app → create todos
↓
app handles everything
↓
no terminal needed
↓
access from iphone too
```

## configuration

### minimal (default)

```json
{
  "apiKey": "your-key",
  "apiUrl": "https://api.beadster.com"
}
```

sync daemon finds everything automatically

### custom

```json
{
  "apiKey": "your-key",
  "apiUrl": "https://api.beadster.com",
  "auto_init": {
    "enabled": true,
    "git_repos_only": true
  },
  "sources": {
    "inbox_path": "~/.beadster/inbox",
    "auto_discover": true,
    "ignore_patterns": ["**/node_modules/**"]
  },
  "sync": {
    "interval": 30,
    "push_on_create": true
  }
}
```

## best practices

coding projects:
- let mcp auto-init .beads/ in git repos
- use bd for dependencies and ready work
- sync via daemon

non-coding work:
- use inbox
- filter by labels
- access from any device

team work:
- use cloud as single source of truth
- local .beads/ is cache
- conflicts resolved in cloud

mobile:
- create cloud-only sources
- no local .beads/ needed
- everything via api

offline:
- local .beads/ works without internet
- sync daemon queues changes
- syncs when online
