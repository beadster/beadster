# beads initialization from macOS app

one-click beads initialization for git projects directly from macOS app

## concept

users can discover and initialize beads tracking for any git repository without using the bd CLI.

## current workflow (manual)

```bash
cd ~/projects/my-app
bd init
git add .beads/issues.jsonl
echo ".beads/*.db" >> .gitignore
```

## new workflow (one-click)

```
macOS app:
  1. Scan folder → finds 20 git repos
  2. Show: "10 projects have beads, 10 need setup"
  3. User clicks "Initialize beads" next to project
  4. App creates .beads/, configures .gitignore
  5. Done! Project ready to track issues
```

## ui flow

### project discovery view

```
📂 Scan Folder

Projects found:
✅ beadster         (beads initialized)
✅ tinydot          (beads initialized)
⚠️  website         (git repo, no beads)  [Initialize]
⚠️  landing-page    (git repo, no beads)  [Initialize]
⚠️  experiments     (no git, no beads)    [Initialize anyway]

[Scan Another Folder]
```

### initialize confirmation

```
Initialize beads for "website"?

This will create:
  .beads/website.db        (local SQLite database)
  .beads/issues.jsonl      (git-tracked issue data)
  .gitignore              (updated to ignore *.db)

Project prefix: website
Issues will be named: website-1, website-2, etc.

[Cancel]  [Initialize]
```

### after initialization

```
✅ Beads initialized for "website"

Created:
  .beads/website.db
  .beads/issues.jsonl

Updated:
  .gitignore

Ready to create issues!
You can now use bd CLI or this app to manage issues.

[Start Using]
```

## implementation

### 1. scan for git repos without beads

```swift
func scanForGitRepos(_ rootURL: URL) async -> [GitRepoInfo] {
    var repos: [GitRepoInfo] = []

    let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey]
    )

    while let url = enumerator?.nextObject() as? URL {
        // skip hidden directories except .git
        if url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != ".git" {
            continue
        }

        let gitDir = url.appendingPathComponent(".git")
        let beadsDir = url.appendingPathComponent(".beads")

        let hasGit = FileManager.default.fileExists(atPath: gitDir.path)
        let hasBeads = BeadsHelper.hasBeadsDatabase(at: url)

        if hasGit && !hasBeads {
            repos.append(GitRepoInfo(
                url: url,
                name: url.lastPathComponent,
                hasGit: true,
                hasBeads: false
            ))
        }
    }

    return repos
}

struct GitRepoInfo {
    let url: URL
    let name: String
    let hasGit: Bool
    let hasBeads: Bool
}
```

### 2. initialize beads (sandboxed)

```swift
func initializeBeads(at projectURL: URL) async throws {
    // ensure security-scoped access
    guard projectURL.startAccessingSecurityScopedResource() else {
        throw BeadsInitError.accessDenied
    }
    defer {
        projectURL.stopAccessingSecurityScopedResource()
    }

    // check if .beads already exists
    let beadsDir = projectURL.appendingPathComponent(".beads")
    if FileManager.default.fileExists(atPath: beadsDir.path) {
        throw BeadsInitError.alreadyInitialized
    }

    // 1. create .beads directory
    try FileManager.default.createDirectory(
        at: beadsDir,
        withIntermediateDirectories: false
    )

    // 2. create database
    let projectName = projectURL.lastPathComponent
    let dbPath = beadsDir.appendingPathComponent("\(projectName).db")
    try createBeadsDatabase(at: dbPath.path, prefix: projectName)

    // 3. create empty issues.jsonl
    let jsonlPath = beadsDir.appendingPathComponent("issues.jsonl")
    try "".write(to: jsonlPath, atomically: true, encoding: .utf8)

    // 4. update .gitignore
    try updateGitignore(at: projectURL)

    // 5. add to projects list
    await addProject(projectURL)
}
```

### 3. create database with schema

```swift
func createBeadsDatabase(at path: String, prefix: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else {
        throw BeadsInitError.databaseCreationFailed
    }
    defer { sqlite3_close(db) }

    // load schema from bundle
    guard let schemaURL = Bundle.main.url(
        forResource: "beads_schema",
        withExtension: "sql"
    ) else {
        throw BeadsInitError.schemaNotFound
    }

    let schema = try String(contentsOf: schemaURL, encoding: .utf8)

    // execute schema
    guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
        let errorMsg = String(cString: sqlite3_errmsg(db))
        print("Database creation error: \(errorMsg)")
        throw BeadsInitError.databaseCreationFailed
    }

    // set issue prefix in config
    let configSQL = "INSERT INTO config (key, value) VALUES ('prefix', '\(prefix)');"
    guard sqlite3_exec(db, configSQL, nil, nil, nil) == SQLITE_OK else {
        throw BeadsInitError.configFailed
    }

    print("✅ Created beads database: \(path)")
}
```

### 4. update .gitignore

```swift
func updateGitignore(at projectURL: URL) throws {
    let gitignorePath = projectURL.appendingPathComponent(".gitignore")

    // read existing .gitignore or create new
    var content = ""
    if FileManager.default.fileExists(atPath: gitignorePath.path) {
        content = try String(contentsOf: gitignorePath, encoding: .utf8)
    }

    // check if already has beads rules
    if content.contains(".beads/*.db") {
        print("ℹ️  .gitignore already configured for beads")
        return
    }

    // add beads rules
    let beadsRules = """

    # Beads issue tracker (database is cache, JSONL is source of truth)
    .beads/*.db

    """

    content += beadsRules

    // write back
    try content.write(to: gitignorePath, atomically: true, encoding: .utf8)

    print("✅ Updated .gitignore")
}
```

### 5. error handling

```swift
enum BeadsInitError: LocalizedError {
    case accessDenied
    case alreadyInitialized
    case databaseCreationFailed
    case schemaNotFound
    case configFailed
    case gitignoreUpdateFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access project folder. Please grant permission."
        case .alreadyInitialized:
            return "Beads is already initialized for this project."
        case .databaseCreationFailed:
            return "Failed to create beads database."
        case .schemaNotFound:
            return "Beads schema file not found in app bundle."
        case .configFailed:
            return "Failed to configure beads database."
        case .gitignoreUpdateFailed:
            return "Failed to update .gitignore file."
        }
    }
}
```

## gitignore rules

what gets ignored (database cache):
```
.beads/*.db
```

what gets committed (source of truth):
```
.beads/issues.jsonl
.beads/config.toml    (if exists)
```

## verification

after initialization, verify:
```swift
func verifyBeadsInit(at projectURL: URL) -> Bool {
    let beadsDir = projectURL.appendingPathComponent(".beads")

    // check .beads exists
    guard FileManager.default.fileExists(atPath: beadsDir.path) else {
        return false
    }

    // check database exists
    guard BeadsHelper.hasBeadsDatabase(at: projectURL) else {
        return false
    }

    // check issues.jsonl exists
    let jsonlPath = beadsDir.appendingPathComponent("issues.jsonl")
    guard FileManager.default.fileExists(atPath: jsonlPath.path) else {
        return false
    }

    // check .gitignore configured
    let gitignorePath = projectURL.appendingPathComponent(".gitignore")
    if FileManager.default.fileExists(atPath: gitignorePath.path) {
        let content = try? String(contentsOf: gitignorePath, encoding: .utf8)
        if !(content?.contains(".beads/*.db") ?? false) {
            print("⚠️  .gitignore not configured for beads")
        }
    }

    return true
}
```

## user experience

### before
```
terminal:
$ cd ~/projects/new-app
$ bd init
$ git add .beads/issues.jsonl
$ echo ".beads/*.db" >> .gitignore
$ git commit -m "Initialize beads issue tracker"
```

### after
```
macOS app:
1. Scan ~/projects
2. Click "Initialize" next to new-app
3. Done!
```

no terminal, no commands, just works.

## edge cases

### project without git

still allow initialization:
```
⚠️  This project is not a git repository.

Beads works best with git for syncing issues across machines.
You can still use beads for local issue tracking.

[Cancel]  [Initialize Anyway]
```

### permission denied

```
❌ Cannot access folder

macOS sandbox requires permission to access this folder.

[Select Folder Again]
```

### already initialized

```
ℹ️  Beads already initialized

This project already has beads set up.
Database: .beads/beadster.db
Issues: .beads/issues.jsonl

[OK]
```

## benefits

- no terminal needed
- no bd CLI installation required (for setup only)
- visual feedback on what's being created
- automatic .gitignore configuration
- works for non-technical users
- batch initialization (future: "Initialize all 10 repos")

## future enhancements

### batch initialization
```
Found 10 git repos without beads

[Initialize All]  [Select Individual]
```

### template selection
```
Initialize beads with template:

( ) Default       - basic issue tracking
( ) Bug tracker   - includes severity, affected version
( ) Agile         - includes story points, sprint
( ) Custom        - configure fields

[Initialize]
```

### git commit option
```
✅ Beads initialized

[ ] Commit to git now
    Message: "Initialize beads issue tracker"

[Done]  [Commit & Done]
```

## notes

- beads database name must match project folder name (bd CLI convention)
- issues.jsonl starts empty, gets populated when first issue is created
- bd CLI will work immediately after initialization
- beadster sync daemon will detect new .beads and start watching
- users can mix bd CLI and macOS app without conflicts

## testing

manual test checklist:
- [ ] initialize beads in fresh git repo
- [ ] verify database created with correct name
- [ ] verify issues.jsonl created (empty)
- [ ] verify .gitignore updated
- [ ] create issue with bd CLI, verify it appears in app
- [ ] create issue with app, verify bd CLI can see it
- [ ] initialize beads in non-git folder
- [ ] try to initialize already-initialized project (should fail gracefully)
