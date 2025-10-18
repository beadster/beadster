# beadster macos app - POC

native swiftui macos app for syncing and viewing bd issues

## what's implemented

### data models
- `Models.swift` - source, issue, dependency models
- json codable with snake_case mapping
- sourceId tracking for cloud sync

### api client
- `APIClient.swift` - rest api client for beadster dev api
- hardcoded dev token for poc
- endpoints: getSources(), getIssues(), syncIssues()

### local storage
- `JSONLManager.swift` - read/write .beads/issues.jsonl
- `ProjectStore.swift` - manage projects with security bookmarks
- sandbox-safe folder selection with NSOpenPanel
- save/load projects from UserDefaults

### sync daemon
- `SyncDaemon.swift` - background sync service
- file system watching with DispatchSource
- monitors .beads/issues.jsonl for changes
- periodic sync every 5 minutes
- bidirectional sync: local ↔ cloud
- merge logic (last-write-wins)

### ui
- `MainView.swift` - split view with projects sidebar and issues list
- `SettingsView.swift` - settings window with api info
- filter issues by status (all/open/closed)
- priority badges (P0-P4)
- label badges
- checkbox to toggle issue status
- error display and loading states
- comprehensive logging

### features working
- ✅ add projects via folder selection
- ✅ scan folders for .beads directories (root and subdirectories)
- ✅ security bookmarks for sandbox access
- ✅ read issues from .beads/issues.jsonl
- ✅ display issues with filtering
- ✅ toggle issue status (open/closed)
- ✅ show priority and labels
- ✅ file system watching (auto-sync on file changes)
- ✅ bidirectional sync with cloud api
- ✅ periodic sync timer (every 5 min)
- ✅ merge conflicts resolution
- ✅ comprehensive logging for debugging

## what's NOT implemented yet (for later)

- ❌ context capture with claude logs
- ❌ sign in with apple auth (using hardcoded token)
- ❌ source registration on cloud (manual sourceId for now)

## how to test

1. open Beadster.xcodeproj in xcode
2. build and run (cmd+r)
3. click "add projects" button
4. select a folder containing git repos with .beads/ directories
5. app will scan and find all projects
6. select a project from sidebar
7. issues from .beads/issues.jsonl will display
8. click checkbox to toggle issue status

## file structure

```
Beadster/
├── BeadsterApp.swift          # app entry point
├── MainView.swift             # main split view ui
├── SettingsView.swift         # settings window
├── Models.swift               # data models
├── APIClient.swift            # api client
├── JSONLManager.swift         # jsonl read/write
├── ProjectStore.swift         # project management
├── IssueStore.swift           # issue management
├── Beadster.entitlements      # sandbox entitlements
└── Assets.xcassets            # app icon and assets
```

## entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

## next steps

1. implement sync daemon
2. add file system watching
3. implement bidirectional sync
4. add context capture with ~/.claude access
5. add sign in with apple
6. replace hardcoded token with user auth

## POC scope

for poc we have:
- simple ui to view issues
- filter by status
- see labels and priority
- project discovery
- local .beads/issues.jsonl reading

enough to validate the concept!
