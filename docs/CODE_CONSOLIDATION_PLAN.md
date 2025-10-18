# code consolidation plan

consolidate CLI sync daemon into macOS app codebase - share all common code

## current duplication

### duplicated files (similar code):

| file | CLI (sync) | macOS (Beadster) | action |
|------|-----------|------------------|--------|
| Models.swift | 99 lines | 139 lines | merge → Shared/Models.swift |
| BeadsDatabase.swift | 139 lines | 170 lines | merge → Shared/BeadsDatabase.swift |
| SyncDaemon.swift | 156 lines | 519 lines | merge (macOS more complete) |
| APIClient vs CloudAPI | CloudAPI 90 lines | APIClient 202 lines | use APIClient (better) |

### CLI-only files (move to macOS):

| file | lines | action |
|------|-------|--------|
| main.swift | 30 | move to Beadster/CLI/main.swift |
| FileWatcher.swift | 49 | move to Shared/ (both might need) |
| SessionTracker.swift | 176 | move to Shared/ |
| BeadsterExtension.swift | 295 | move to Shared/ (new, both need) |

### macOS-only files (keep in Beadster):

| file | purpose |
|------|---------|
| BeadsterApp.swift | SwiftUI app entry |
| MainView.swift | SwiftUI main UI |
| ContentView.swift | SwiftUI placeholder |
| SettingsView.swift | SwiftUI settings |
| IssueStore.swift | SwiftUI observable state |
| ProjectStore.swift | SwiftUI observable state |
| JSONLManager.swift | JSONL operations |
| SourceIDGenerator.swift | source ID generation |
| DeviceID.swift | hardware UUID (macOS specific) |

## proposed structure

```
src/Beadster/
├── Beadster/                    (macOS app target)
│   ├── BeadsterApp.swift        (app entry)
│   ├── Views/                   (SwiftUI views)
│   │   ├── MainView.swift
│   │   ├── SettingsView.swift
│   │   └── ContentView.swift
│   ├── Stores/                  (observable state)
│   │   ├── IssueStore.swift
│   │   └── ProjectStore.swift
│   └── Utilities/               (app-specific)
│       ├── JSONLManager.swift
│       ├── SourceIDGenerator.swift
│       └── DeviceID.swift
│
├── Shared/                      (shared between CLI and app)
│   ├── Models.swift             (merged from both)
│   ├── BeadsDatabase.swift      (merged from both)
│   ├── BeadsterExtension.swift  (new, for beadster_sync table)
│   ├── APIClient.swift          (use macOS version, better)
│   ├── SyncDaemon.swift         (merged, keep macOS features)
│   ├── SessionTracker.swift     (from CLI)
│   └── FileWatcher.swift        (from CLI)
│
└── CLI/                         (CLI target)
    └── main.swift               (CLI entry point)

Package.swift                    (Swift package with 2 targets)
```

## package.swift structure

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Beadster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "beadster-sync", targets: ["BeadsterCLI"]),
        .executable(name: "Beadster", targets: ["BeadsterApp"])
    ],
    targets: [
        // shared code (used by both CLI and app)
        .target(
            name: "BeadsterShared",
            dependencies: [],
            path: "Shared"
        ),

        // CLI daemon
        .executableTarget(
            name: "BeadsterCLI",
            dependencies: ["BeadsterShared"],
            path: "CLI"
        ),

        // macOS app
        .executableTarget(
            name: "BeadsterApp",
            dependencies: ["BeadsterShared"],
            path: "Beadster"
        )
    ]
)
```

## migration steps

### step 1: create new structure

```bash
cd src/Beadster

# create shared directory
mkdir -p Shared

# create CLI directory
mkdir -p CLI

# create organized app directories
mkdir -p Beadster/Views
mkdir -p Beadster/Stores
mkdir -p Beadster/Utilities
```

### step 2: move shared code

```bash
# move from CLI to Shared
mv ../sync/Sources/BeadsterExtension.swift Shared/
mv ../sync/Sources/SessionTracker.swift Shared/
mv ../sync/Sources/FileWatcher.swift Shared/

# move CLI entry point
mv ../sync/Sources/main.swift CLI/

# copy macOS files to Shared (will merge)
cp Beadster/APIClient.swift Shared/
cp Beadster/BeadsDatabase.swift Shared/
cp Beadster/Models.swift Shared/
cp Beadster/SyncDaemon.swift Shared/
```

### step 3: merge duplicates

merge these files manually (keep best from both):

1. **Shared/Models.swift**
   - merge Issue, Source, Session models
   - keep all fields from both versions
   - use Codable for JSON serialization

2. **Shared/BeadsDatabase.swift**
   - merge query methods
   - keep macOS date parsing logic
   - add CLI's issueExists() method
   - change path from `beads.db` → `beads.db`

3. **Shared/SyncDaemon.swift**
   - use macOS version as base (more complete)
   - add CLI's simple file watching
   - merge sync logic
   - add BeadsterExtension integration

4. **Shared/APIClient.swift**
   - use macOS version (more complete)
   - rename from APIClient to BeadsterAPI for clarity

### step 4: reorganize macOS app

```bash
# move views
mv Beadster/MainView.swift Beadster/Views/
mv Beadster/SettingsView.swift Beadster/Views/
mv Beadster/ContentView.swift Beadster/Views/

# move stores
mv Beadster/IssueStore.swift Beadster/Stores/
mv Beadster/ProjectStore.swift Beadster/Stores/

# move utilities
mv Beadster/JSONLManager.swift Beadster/Utilities/
mv Beadster/SourceIDGenerator.swift Beadster/Utilities/
mv Beadster/DeviceID.swift Beadster/Utilities/
```

### step 5: update imports

in all Shared/ files:
```swift
// old (app-specific)
import SwiftUI  // REMOVE if not needed

// new (shared)
import Foundation
import SQLite3
```

in macOS app files:
```swift
import SwiftUI
import BeadsterShared  // NEW - import shared code
```

in CLI files:
```swift
import Foundation
import BeadsterShared  // NEW - import shared code
```

### step 6: create Package.swift

```bash
cd src/Beadster
# create Package.swift (see structure above)
```

### step 7: update Xcode project

in Xcode:
- add Shared/ as a framework target
- link BeadsterApp target to Shared framework
- update file references
- update import statements

### step 8: test build

```bash
# build CLI
swift build -c release --product beadster-sync

# build macOS app (in Xcode)
# or via xcodebuild
```

### step 9: cleanup

```bash
# remove old CLI directory
rm -rf ../sync

# update paths in docs
# update scripts/sync-daemon.sh
```

## benefits

1. **single source of truth** - one APIClient, one BeadsDatabase
2. **shared sync logic** - BeadsterExtension used by both
3. **easier maintenance** - fix bug once, both get it
4. **consistent behavior** - same sync algorithm in CLI and app
5. **code reuse** - ~500 lines of shared code vs ~1000 lines duplicated

## differences between CLI and app

### CLI daemon:
- runs in background
- simple file watching
- no UI
- logs to console
- started via `beadster-sync`

### macOS app:
- SwiftUI interface
- file system watching with security-scoped bookmarks
- settings UI
- project management
- manual sync button
- notifications
- runs as regular app

both use **same** Shared/ code for:
- beads database access
- cloud API communication
- sync algorithm
- session tracking
- extension tables

## migration timeline

1. create structure (10 min)
2. move files (5 min)
3. merge Models.swift (15 min)
4. merge BeadsDatabase.swift (20 min)
5. merge SyncDaemon.swift (30 min)
6. update imports (10 min)
7. create Package.swift (10 min)
8. test CLI build (5 min)
9. test macOS build (10 min)
10. cleanup and docs (10 min)

**total: ~2 hours**

## ready to proceed?

when approved:
1. create new structure
2. move files
3. merge duplicates
4. update Package.swift
5. test builds
6. commit with message: "refactor: consolidate CLI sync into macOS app codebase"
