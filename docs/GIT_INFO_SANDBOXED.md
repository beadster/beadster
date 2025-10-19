# reading git info in sandboxed macOS app

how to get git repository information without executing shell commands

## the problem

sandboxed macOS apps cannot:
- ❌ execute external binaries (`/usr/bin/git`)
- ❌ use `Process()` to run shell commands
- ❌ call `git remote get-url origin`
- ❌ call `git branch --show-current`

## the solution

read git config files directly:
- ✅ read `.git/config` file
- ✅ read `.git/HEAD` file
- ✅ parse text files using FileManager and String operations
- ✅ works in sandboxed apps with security-scoped bookmarks

## implementation

### 1. detect git repository

```swift
func isGitRepository(at url: URL) -> Bool {
    let gitDir = url.appendingPathComponent(".git")
    var isDirectory: ObjCBool = false

    guard FileManager.default.fileExists(
        atPath: gitDir.path,
        isDirectory: &isDirectory
    ) else {
        return false
    }

    return isDirectory.boolValue
}
```

### 2. get remote URL from .git/config

```swift
func getGitRemoteUrl(at projectURL: URL) -> String? {
    let gitConfigPath = projectURL.appendingPathComponent(".git/config")

    guard let configContent = try? String(
        contentsOf: gitConfigPath,
        encoding: .utf8
    ) else {
        return nil
    }

    // parse .git/config for [remote "origin"] url
    return parseGitRemoteUrl(from: configContent)
}

func parseGitRemoteUrl(from config: String) -> String? {
    let lines = config.components(separatedBy: .newlines)
    var inOriginSection = false

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // check for [remote "origin"]
        if trimmed.contains("[remote \"origin\"]") {
            inOriginSection = true
            continue
        }

        // check for new section (ends origin section)
        if trimmed.hasPrefix("[") && inOriginSection {
            inOriginSection = false
        }

        // look for url = in origin section
        if inOriginSection && trimmed.hasPrefix("url = ") {
            let url = trimmed.replacingOccurrences(of: "url = ", with: "")
            return normalizeGitUrl(url)
        }
    }

    return nil
}

func normalizeGitUrl(_ url: String) -> String {
    // convert SSH to HTTPS
    // git@github.com:user/repo.git → https://github.com/user/repo

    if url.hasPrefix("git@github.com:") {
        let repo = url
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: ".git", with: "")
        return "https://github.com/\(repo)"
    }

    // strip .git suffix from HTTPS URLs
    if url.hasPrefix("https://") {
        return url.replacingOccurrences(of: ".git", with: "")
    }

    return url
}
```

### 3. get current branch from .git/HEAD

```swift
func getCurrentBranch(at projectURL: URL) -> String? {
    let headPath = projectURL.appendingPathComponent(".git/HEAD")

    guard let headContent = try? String(
        contentsOf: headPath,
        encoding: .utf8
    ) else {
        return nil
    }

    // .git/HEAD contains either:
    // "ref: refs/heads/main\n"  (on a branch)
    // "abc123def456...\n"        (detached HEAD)

    let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("ref: refs/heads/") {
        return trimmed.replacingOccurrences(of: "ref: refs/heads/", with: "")
    }

    // detached HEAD (return nil or "detached")
    return nil
}
```

### 4. get default branch

```swift
func getDefaultBranch(at projectURL: URL) -> String {
    // try to detect from .git/refs/remotes/origin/HEAD
    let originHeadPath = projectURL
        .appendingPathComponent(".git/refs/remotes/origin/HEAD")

    if let content = try? String(contentsOf: originHeadPath, encoding: .utf8) {
        // content: "ref: refs/remotes/origin/main\n"
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let branchName = trimmed.split(separator: "/").last {
            return String(branchName)
        }
    }

    // fallback to "main" (most common default)
    return "main"
}
```

### 5. complete git info helper

```swift
struct GitInfo {
    let remoteUrl: String?
    let remoteName: String?      // "user/repo"
    let currentBranch: String?
    let defaultBranch: String
    let isGitRepo: Bool
}

class GitInfoReader {
    static func getGitInfo(at projectURL: URL) -> GitInfo {
        guard isGitRepository(at: projectURL) else {
            return GitInfo(
                remoteUrl: nil,
                remoteName: nil,
                currentBranch: nil,
                defaultBranch: "main",
                isGitRepo: false
            )
        }

        let remoteUrl = getGitRemoteUrl(at: projectURL)
        let currentBranch = getCurrentBranch(at: projectURL)
        let defaultBranch = getDefaultBranch(at: projectURL)

        return GitInfo(
            remoteUrl: remoteUrl,
            remoteName: extractRepoName(from: remoteUrl),
            currentBranch: currentBranch,
            defaultBranch: defaultBranch,
            isGitRepo: true
        )
    }

    private static func extractRepoName(from url: String?) -> String? {
        guard let url = url else { return nil }

        // https://github.com/user/repo → "user/repo"
        if url.hasPrefix("https://github.com/") {
            let parts = url.replacingOccurrences(of: "https://github.com/", with: "")
            return parts
        }

        return nil
    }
}
```

## example .git/config file

```ini
[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
	logallrefupdates = true
	ignorecase = true
	precomposeunicode = true
[remote "origin"]
	url = git@github.com:user/beadster.git
	fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
	remote = origin
	merge = refs/heads/main
```

## example .git/HEAD file

```
ref: refs/heads/main
```

or when detached:

```
abc123def456789abcdef0123456789abcdef01
```

## usage in sync daemon

```swift
func syncIssueToCloud(issue: Issue, project: ProjectInfo) async throws {
    // resolve bookmark
    var isStale = false
    guard let projectURL = try? URL(
        resolvingBookmarkData: project.bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else {
        throw SyncError.cantAccessProject
    }

    // access security scoped resource
    guard projectURL.startAccessingSecurityScopedResource() else {
        throw SyncError.accessDenied
    }
    defer {
        projectURL.stopAccessingSecurityScopedResource()
    }

    // read git info from .git/config and .git/HEAD
    let gitInfo = GitInfoReader.getGitInfo(at: projectURL)

    // enrich issue with git context
    var enrichedIssue = issue
    enrichedIssue.gitBranch = gitInfo.currentBranch

    // sync to cloud
    await cloudAPI.upsertIssue(enrichedIssue)

    // update source with git repo info (if not set)
    if project.gitRepoUrl == nil && gitInfo.remoteUrl != nil {
        await cloudAPI.updateSource(
            sourceId: project.sourceId,
            gitRepoUrl: gitInfo.remoteUrl,
            gitRepoName: gitInfo.remoteName
        )
    }
}
```

## usage in project store

```swift
func addProject(_ projectURL: URL) async {
    // ... existing code to create bookmark ...

    // detect git info
    let gitInfo = GitInfoReader.getGitInfo(at: projectURL)

    let project = ProjectInfo(
        id: UUID().uuidString,
        name: projectURL.lastPathComponent,
        path: projectURL.path,
        bookmark: bookmark,
        sourceId: sourceId,
        gitRepoUrl: gitInfo.remoteUrl,       // ← new
        gitRepoName: gitInfo.remoteName,     // ← new
        gitDefaultBranch: gitInfo.defaultBranch // ← new
    )

    await MainActor.run {
        projects.append(project)
    }
    saveProjects()
}

struct ProjectInfo: Identifiable {
    let id: String
    let name: String
    let path: String
    let bookmark: Data
    var sourceId: String?
    var gitRepoUrl: String?       // ← new
    var gitRepoName: String?      // ← new
    var gitDefaultBranch: String? // ← new
}
```

## testing

manual verification:

```swift
// test git info reader
let projectURL = URL(fileURLWithPath: "/Users/anton/projects/beadster")
let gitInfo = GitInfoReader.getGitInfo(at: projectURL)

print("Git repo: \(gitInfo.remoteUrl ?? "none")")
print("Repo name: \(gitInfo.remoteName ?? "none")")
print("Current branch: \(gitInfo.currentBranch ?? "none")")
print("Default branch: \(gitInfo.defaultBranch)")
print("Is git repo: \(gitInfo.isGitRepo)")

// expected output:
// Git repo: https://github.com/user/beadster
// Repo name: user/beadster
// Current branch: main
// Default branch: main
// Is git repo: true
```

## edge cases

### no .git directory

```swift
GitInfo(
    remoteUrl: nil,
    remoteName: nil,
    currentBranch: nil,
    defaultBranch: "main",
    isGitRepo: false
)
```

### detached HEAD state

```swift
// .git/HEAD contains SHA, not "ref: refs/heads/..."
GitInfo(
    remoteUrl: "https://github.com/user/repo",
    remoteName: "user/repo",
    currentBranch: nil,  // detached HEAD
    defaultBranch: "main",
    isGitRepo: true
)
```

### no remote configured

```swift
// .git/config has no [remote "origin"] section
GitInfo(
    remoteUrl: nil,
    remoteName: nil,
    currentBranch: "main",
    defaultBranch: "main",
    isGitRepo: true
)
```

### multiple remotes

current implementation only reads `[remote "origin"]`. could be extended to read all remotes:

```swift
func getAllRemotes(at projectURL: URL) -> [String: String] {
    // parse all [remote "name"] sections
    // return ["origin": "https://...", "upstream": "https://..."]
}
```

## performance

reading git config files is fast:
- `.git/config`: typically < 1 KB
- `.git/HEAD`: typically < 50 bytes
- no process spawning overhead
- works offline
- no dependencies on git CLI being installed

## limitations

cannot do (requires git CLI):
- ❌ get commit history
- ❌ get uncommitted changes
- ❌ get current commit SHA
- ❌ check if branch is ahead/behind remote
- ❌ get git status

can do (read files only):
- ✅ get remote URL
- ✅ get current branch name
- ✅ get default branch
- ✅ detect if project is git repo
- ✅ works in sandboxed apps

for advanced git operations, users would need bd CLI or git CLI installed.

## benefits

- works in sandboxed macOS app
- no external dependencies
- fast (just file reads)
- works offline
- sufficient for basic repo tracking
- enables filtering issues by repository

## summary

**solution:** read `.git/config` and `.git/HEAD` files directly instead of running git commands.

**what we can track:**
- git remote URL (for identifying repository)
- current branch name (for context)
- default branch (for UI)

**what we cannot track without git CLI:**
- commit history
- uncommitted changes
- current commit SHA

this is enough for the main use case: **filtering issues by repository in the web app**.
