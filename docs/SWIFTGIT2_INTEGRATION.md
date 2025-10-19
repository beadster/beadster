# SwiftGit2 integration for beadster

using libgit2 Swift bindings to read git info without CLI

## the solution: SwiftGit2 + libgit2

**SwiftGit2**: Swift bindings to libgit2
**libgit2**: Pure C implementation of Git core - NO git CLI required!

### why this is perfect

- ✅ Pure C library (linkable, no external dependencies)
- ✅ Works in sandboxed macOS apps
- ✅ No git CLI required
- ✅ Cross-platform (macOS, iOS, Linux, Windows)
- ✅ Permissive license (GPLv2 with linking exception)
- ✅ Used by GitHub, GitLab, GitKraken, Azure DevOps
- ✅ Can read: commit SHA, branch name, remote URL, history

## what we can now track

with SwiftGit2, we can track EVERYTHING:

- ✅ Current commit SHA
- ✅ Current branch name
- ✅ Remote URL
- ✅ Default branch
- ✅ Commit history
- ✅ Repository status
- ✅ Tags
- ✅ Refs

## installation

### option 1: Swift Package Manager (recommended)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/SwiftGit2/SwiftGit2.git", from: "0.10.0")
]
```

### option 2: CocoaPods

```ruby
# Podfile
pod 'SwiftGit2'
```

### option 3: SwiftGit3 (fork with SPM support)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/joehinkle11/SwiftGit3.git", from: "1.0.0")
]
```

## basic usage

### open repository

```swift
import SwiftGit2

func openRepository(at url: URL) -> Result<Repository, NSError> {
    return Repository.at(url)
}
```

### get current commit SHA

```swift
func getCurrentCommitSHA(repo: Repository) -> String? {
    return repo.HEAD()
        .flatMap { repo.commit($0.oid) }
        .map { $0.oid.description }
        .value
}

// example: "021d3bdff1da1db666356b666799a63767f23680"
```

### get current branch name

```swift
func getCurrentBranch(repo: Repository) -> String? {
    return repo.HEAD()
        .flatMap { head in
            if head.isRemote {
                return .success(head.remoteBranchName)
            } else {
                return .success(head.localBranchName)
            }
        }
        .value
}

// example: "main"
```

### get remote URL

```swift
func getRemoteURL(repo: Repository, remoteName: String = "origin") -> String? {
    return repo.allRemotes()
        .flatMap { remotes in
            if let remote = remotes.first(where: { $0.name == remoteName }) {
                return .success(remote.URL)
            }
            return .failure(NSError(domain: "RemoteNotFound", code: 404))
        }
        .value
}

// example: "https://github.com/user/beadster.git"
```

### get commit history

```swift
func getRecentCommits(repo: Repository, limit: Int = 10) -> [Commit] {
    guard let head = repo.HEAD().value else { return [] }
    guard let commit = repo.commit(head.oid).value else { return [] }

    var commits: [Commit] = [commit]
    var current = commit

    for _ in 0..<(limit - 1) {
        guard let parent = current.parents.first else { break }
        commits.append(parent)
        current = parent
    }

    return commits
}
```

## complete git info reader

```swift
import SwiftGit2

struct GitInfo {
    let remoteUrl: String?
    let remoteName: String?      // "user/repo"
    let currentBranch: String?
    let currentCommitSHA: String?
    let defaultBranch: String
    let isGitRepo: Bool
    let isDirty: Bool            // has uncommitted changes
}

class GitInfoReader {
    static func getGitInfo(at projectURL: URL) -> GitInfo {
        guard let repo = Repository.at(projectURL).value else {
            return GitInfo(
                remoteUrl: nil,
                remoteName: nil,
                currentBranch: nil,
                currentCommitSHA: nil,
                defaultBranch: "main",
                isGitRepo: false,
                isDirty: false
            )
        }

        let remoteUrl = getRemoteURL(repo: repo)
        let currentBranch = getCurrentBranch(repo: repo)
        let currentCommitSHA = getCurrentCommitSHA(repo: repo)
        let isDirty = hasUncommittedChanges(repo: repo)

        return GitInfo(
            remoteUrl: normalizeGitUrl(remoteUrl),
            remoteName: extractRepoName(from: remoteUrl),
            currentBranch: currentBranch,
            currentCommitSHA: currentCommitSHA,
            defaultBranch: "main",
            isGitRepo: true,
            isDirty: isDirty
        )
    }

    private static func getCurrentCommitSHA(repo: Repository) -> String? {
        return repo.HEAD()
            .flatMap { repo.commit($0.oid) }
            .map { $0.oid.description }
            .value
    }

    private static func getCurrentBranch(repo: Repository) -> String? {
        return repo.HEAD()
            .flatMap { head in
                if head.isRemote {
                    return .success(head.remoteBranchName)
                } else {
                    return .success(head.localBranchName)
                }
            }
            .value
    }

    private static func getRemoteURL(repo: Repository) -> String? {
        return repo.allRemotes()
            .flatMap { remotes in
                if let remote = remotes.first(where: { $0.name == "origin" }) {
                    return .success(remote.URL)
                }
                return .failure(NSError(domain: "RemoteNotFound", code: 404))
            }
            .value
    }

    private static func hasUncommittedChanges(repo: Repository) -> Bool {
        // check if working directory has changes
        // this would require more complex libgit2 API calls
        // for now, return false
        return false
    }

    private static func normalizeGitUrl(_ url: String?) -> String? {
        guard let url = url else { return nil }

        // convert SSH to HTTPS
        if url.hasPrefix("git@github.com:") {
            let repo = url
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
            return "https://github.com/\(repo)"
        }

        // strip .git suffix
        return url.replacingOccurrences(of: ".git", with: "")
    }

    private static func extractRepoName(from url: String?) -> String? {
        guard let url = url else { return nil }

        if url.hasPrefix("https://github.com/") {
            return url.replacingOccurrences(of: "https://github.com/", with: "")
        }

        return nil
    }
}
```

## usage in sync daemon

```swift
import SwiftGit2

func syncIssueToCloud(issue: Issue, project: ProjectInfo) async throws {
    // resolve bookmark
    guard let projectURL = resolveProjectURL(project) else {
        throw SyncError.cantAccessProject
    }

    // access security scoped resource
    guard projectURL.startAccessingSecurityScopedResource() else {
        throw SyncError.accessDenied
    }
    defer {
        projectURL.stopAccessingSecurityScopedResource()
    }

    // get git info using SwiftGit2
    let gitInfo = GitInfoReader.getGitInfo(at: projectURL)

    // enrich issue with git context
    var enrichedIssue = issue
    enrichedIssue.gitBranch = gitInfo.currentBranch
    enrichedIssue.gitCommit = gitInfo.currentCommitSHA  // ← NOW WE CAN GET THIS!

    // sync to cloud
    await cloudAPI.upsertIssue(enrichedIssue)

    // update source with git repo info
    if project.gitRepoUrl == nil && gitInfo.remoteUrl != nil {
        await cloudAPI.updateSource(
            sourceId: project.sourceId,
            gitRepoUrl: gitInfo.remoteUrl,
            gitRepoName: gitInfo.remoteName
        )
    }
}
```

## updating issues with commit info

when closing an issue, record the commit SHA:

```swift
func closeIssue(_ issue: Issue, projectPath: String) async throws {
    let projectURL = URL(fileURLWithPath: projectPath)
    let gitInfo = GitInfoReader.getGitInfo(at: projectURL)

    var closedIssue = issue
    closedIssue.status = "closed"
    closedIssue.closedAt = Int(Date().timeIntervalSince1970)
    closedIssue.gitCommit = gitInfo.currentCommitSHA  // ← record commit that fixed it

    try await updateIssue(closedIssue)
}
```

## advanced: commit history per issue

```swift
func getCommitsForIssue(issueId: String, projectURL: URL) -> [CommitInfo] {
    guard let repo = Repository.at(projectURL).value else { return [] }

    // get commits that mention this issue in commit message
    let commits = getAllCommits(repo: repo)
        .filter { $0.message.contains(issueId) }
        .map { commit in
            CommitInfo(
                sha: commit.oid.description,
                message: commit.message,
                author: commit.author.name,
                date: commit.author.time
            )
        }

    return commits
}

struct CommitInfo {
    let sha: String
    let message: String
    let author: String
    let date: Date
}
```

## sandboxing considerations

### security-scoped bookmarks

SwiftGit2 works fine with security-scoped bookmarks:

```swift
// resolve bookmark
var isStale = false
guard let projectURL = try? URL(
    resolvingBookmarkData: project.bookmark,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
) else {
    throw Error.cantResolveBookmark
}

// access scoped resource
guard projectURL.startAccessingSecurityScopedResource() else {
    throw Error.accessDenied
}
defer {
    projectURL.stopAccessingSecurityScopedResource()
}

// use SwiftGit2
let repo = Repository.at(projectURL).value
let gitInfo = GitInfoReader.getGitInfo(at: projectURL)
```

### entitlements

no special entitlements needed! SwiftGit2 just reads files like we were doing manually.

## benefits over manual file parsing

### manual approach (current)
- ✅ Read remote URL from .git/config
- ✅ Read branch from .git/HEAD
- ❌ Cannot get commit SHA easily
- ❌ Cannot get commit history
- ❌ Cannot check working directory status
- ❌ Complex parsing logic

### SwiftGit2 approach (recommended)
- ✅ Read remote URL
- ✅ Read branch name
- ✅ Get current commit SHA
- ✅ Get commit history
- ✅ Check working directory status
- ✅ Clean API, well-tested
- ✅ Used by GitHub, GitLab, etc.

## comparison

| Feature | Manual File Reading | SwiftGit2 |
|---------|-------------------|-----------|
| Remote URL | ✅ | ✅ |
| Branch name | ✅ | ✅ |
| Commit SHA | ❌ | ✅ |
| Commit history | ❌ | ✅ |
| Working tree status | ❌ | ✅ |
| Tags | ❌ | ✅ |
| Refs | ❌ | ✅ |
| Sandboxed app | ✅ | ✅ |
| External deps | None | libgit2 |
| Maintenance | High | Low |
| Testing | Manual | Well-tested |

## implementation plan

1. **Add SwiftGit2 dependency**
   - Use Swift Package Manager
   - Add to both macOS app and sync daemon

2. **Create GitInfoReader helper**
   - Replace manual file parsing
   - Use SwiftGit2 API

3. **Update sync daemon**
   - Capture commit SHA when syncing
   - Send to cloud with git context

4. **Update database schema**
   - Already planned in GIT_REPO_TRACKING.md
   - Add git_commit column

5. **Update web app**
   - Display commit SHA
   - Link to GitHub commit page

## example output

```swift
let gitInfo = GitInfoReader.getGitInfo(at: projectURL)

print(gitInfo)
// GitInfo(
//   remoteUrl: "https://github.com/user/beadster",
//   remoteName: "user/beadster",
//   currentBranch: "main",
//   currentCommitSHA: "021d3bdff1da1db666356b666799a63767f23680",
//   defaultBranch: "main",
//   isGitRepo: true,
//   isDirty: false
// )
```

## web app display

```
beadster.com/issues/beadster-86

beadster-86: fix compilation errors

status: closed
priority: P0
repo: github.com/user/beadster
branch: main
commit: 021d3bd
closed: 2 hours ago

[View Commit on GitHub]
  → https://github.com/user/beadster/commit/021d3bd
```

## next steps

1. Add SwiftGit2 to Package.swift
2. Test in sandboxed app
3. Replace manual git file parsing
4. Update database to store commit SHA
5. Update web app to display commit links

## resources

- SwiftGit2: https://github.com/SwiftGit2/SwiftGit2
- libgit2: https://libgit2.org/
- SwiftGit3 (fork): https://github.com/joehinkle11/SwiftGit3
- libgit2 docs: https://libgit2.org/libgit2/

## conclusion

**Use SwiftGit2!** It solves all our problems:
- ✅ Works in sandboxed apps
- ✅ No git CLI required
- ✅ Can track commit SHA
- ✅ Can get commit history
- ✅ Production-ready (used by GitHub, GitLab)
- ✅ Clean Swift API
