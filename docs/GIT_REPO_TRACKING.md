# git repository tracking

implementation plan for tracking git repos in beadster

## current state

**sources table** (has basic project info):
```sql
CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,  -- 'local', 'virtual', 'inbox'
  path TEXT,
  last_sync INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

**issues table** (no git info yet):
```sql
CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  beads_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  status TEXT NOT NULL,
  -- no git fields yet
);
```

## what we need

### option 1: git info on sources (recommended)

add git repo info to sources table (one repo per source):

```sql
ALTER TABLE sources ADD COLUMN git_repo_url TEXT;     -- "https://github.com/user/repo"
ALTER TABLE sources ADD COLUMN git_repo_name TEXT;    -- "user/repo"
ALTER TABLE sources ADD COLUMN git_default_branch TEXT; -- "main"

CREATE INDEX idx_sources_git_repo ON sources(git_repo_url);
CREATE INDEX idx_sources_git_repo_name ON sources(git_repo_name);
```

**reasoning:**
- one source = one project = one git repo (most common case)
- simpler data model
- easier to filter "show all issues for repo X"
- git info doesn't change often

### option 2: git info on issues

add git context to each issue (more granular):

```sql
ALTER TABLE issues ADD COLUMN git_repo_url TEXT;      -- "https://github.com/user/repo"
ALTER TABLE issues ADD COLUMN git_branch TEXT;        -- "feature/auth"
ALTER TABLE issues ADD COLUMN git_commit TEXT;        -- commit SHA when closed
ALTER TABLE issues ADD COLUMN git_pr_url TEXT;        -- "https://github.com/user/repo/pull/123"
ALTER TABLE issues ADD COLUMN git_pr_number INTEGER;  -- 123

CREATE INDEX idx_issues_git_repo ON issues(git_repo_url);
CREATE INDEX idx_issues_git_branch ON issues(git_branch);
CREATE INDEX idx_issues_git_commit ON issues(git_commit);
```

**reasoning:**
- tracks which branch issue was created on
- links issues to specific PRs and commits
- useful for "what did I fix in this commit?"
- supports monorepos (one source, multiple logical repos)

### recommended: both!

use both approaches:
- **sources table**: repo URL (identifies the repository)
- **issues table**: branch, commit, PR (tracks development context)

```sql
-- Sources: identify the repository
ALTER TABLE sources ADD COLUMN git_repo_url TEXT;
ALTER TABLE sources ADD COLUMN git_repo_name TEXT;

-- Issues: track development context
ALTER TABLE issues ADD COLUMN git_branch TEXT;
ALTER TABLE issues ADD COLUMN git_commit TEXT;
ALTER TABLE issues ADD COLUMN git_pr_url TEXT;
ALTER TABLE issues ADD COLUMN git_pr_number INTEGER;
```

## migration sql

```sql
-- Add git tracking to sources
ALTER TABLE sources ADD COLUMN git_repo_url TEXT;
ALTER TABLE sources ADD COLUMN git_repo_name TEXT;
ALTER TABLE sources ADD COLUMN git_default_branch TEXT DEFAULT 'main';

CREATE INDEX idx_sources_git_repo_url ON sources(git_repo_url);
CREATE INDEX idx_sources_git_repo_name ON sources(git_repo_name);

-- Add git context to issues
ALTER TABLE issues ADD COLUMN git_branch TEXT;
ALTER TABLE issues ADD COLUMN git_commit TEXT;
ALTER TABLE issues ADD COLUMN git_pr_url TEXT;
ALTER TABLE issues ADD COLUMN git_pr_number INTEGER;

CREATE INDEX idx_issues_git_repo_url ON issues(git_repo_url);
CREATE INDEX idx_issues_git_branch ON issues(git_branch);
CREATE INDEX idx_issues_git_commit ON issues(git_commit);
CREATE INDEX idx_issues_git_pr ON issues(git_pr_number);
```

## how to populate git info

### 1. sync daemon (automatic)

when syncing issues, detect git info:

```swift
func syncIssueToCloud(issue: Issue, projectPath: String) async throws {
    // detect git repo
    let gitInfo = getGitInfo(at: projectPath)

    // enrich issue with git context
    let enrichedIssue = Issue(
        id: issue.id,
        title: issue.title,
        // ... other fields
        gitBranch: gitInfo.currentBranch,
        gitRepoUrl: gitInfo.remoteUrl
    )

    // sync to cloud with git info
    await cloudAPI.upsertIssue(enrichedIssue)
}

func getGitInfo(at path: String) -> GitInfo {
    let fm = FileManager.default
    let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

    guard fm.fileExists(atPath: gitDir.path) else {
        return GitInfo(remoteUrl: nil, currentBranch: nil)
    }

    // get remote URL
    let remoteUrl = shell("cd \(path) && git remote get-url origin")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // get current branch
    let currentBranch = shell("cd \(path) && git branch --show-current")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return GitInfo(
        remoteUrl: normalizeGitUrl(remoteUrl),
        currentBranch: currentBranch.isEmpty ? nil : currentBranch
    )
}

func normalizeGitUrl(_ url: String) -> String? {
    // convert SSH to HTTPS
    // git@github.com:user/repo.git → https://github.com/user/repo

    if url.hasPrefix("git@github.com:") {
        let repo = url
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: ".git", with: "")
        return "https://github.com/\(repo)"
    }

    if url.hasPrefix("https://github.com/") {
        return url.replacingOccurrences(of: ".git", with: "")
    }

    return url.isEmpty ? nil : url
}

struct GitInfo {
    let remoteUrl: String?
    let currentBranch: String?
}
```

### 2. source registration (automatic)

when registering source, capture git repo:

```typescript
// API: POST /api/sources
async function registerSource(sourcePayload: SourcePayload) {
  const source = await db.sources.create({
    id: sourcePayload.id,
    name: sourcePayload.name,
    type: sourcePayload.type,
    path: sourcePayload.path,
    git_repo_url: sourcePayload.gitRepoUrl,     // ← new
    git_repo_name: sourcePayload.gitRepoName,   // ← new
    created_at: Date.now(),
    updated_at: Date.now()
  });

  return source;
}
```

### 3. web app (manual or edit)

allow users to set/edit git repo:

```tsx
// Source settings page
<SourceSettings source={source}>
  <Input
    label="Git Repository"
    placeholder="https://github.com/user/repo"
    value={source.git_repo_url}
    onChange={(url) => updateSource({ git_repo_url: url })}
  />
</SourceSettings>
```

## web app filters

### filter by repository

```tsx
// All issues page
<IssuesPage>
  <Filters>
    <RepositoryFilter
      repos={[
        { name: "beadster", url: "https://github.com/user/beadster", count: 45 },
        { name: "tinydot", url: "https://github.com/user/tinydot", count: 23 },
        { name: "website", url: "https://github.com/user/website", count: 12 }
      ]}
      selected={selectedRepo}
      onChange={setSelectedRepo}
    />
  </Filters>

  <IssuesList issues={filteredIssues} />
</IssuesPage>
```

### api endpoint

```typescript
// GET /api/issues?git_repo_url=https://github.com/user/repo
async function getIssues(request: Request) {
  const url = new URL(request.url);
  const gitRepoUrl = url.searchParams.get('git_repo_url');

  let query = db.issues.where('user_id', userId);

  if (gitRepoUrl) {
    // join with sources to filter by repo
    query = query
      .join('sources', 'issues.source_id', 'sources.id')
      .where('sources.git_repo_url', gitRepoUrl);
  }

  const issues = await query.all();
  return Response.json({ issues });
}
```

### repository list

```typescript
// GET /api/repositories
async function getRepositories(request: Request) {
  // get unique repos with issue counts
  const repos = await db.query(`
    SELECT
      s.git_repo_url,
      s.git_repo_name,
      COUNT(i.id) as issue_count,
      COUNT(CASE WHEN i.status = 'open' THEN 1 END) as open_count
    FROM sources s
    LEFT JOIN issues i ON i.source_id = s.id
    WHERE s.user_id = ? AND s.git_repo_url IS NOT NULL
    GROUP BY s.git_repo_url, s.git_repo_name
    ORDER BY issue_count DESC
  `, [userId]);

  return Response.json({ repositories: repos });
}
```

## ui views

### repositories page

```
beadster.com/repositories

Your Repositories

github.com/user/beadster       45 issues  (12 open)
github.com/user/tinydot        23 issues  (5 open)
github.com/user/website        12 issues  (3 open)
github.com/company/main-app    89 issues  (34 open)

[View All Issues]
```

### issues by repo

```
beadster.com/repositories/github.com/user/beadster

beadster (github.com/user/beadster)

45 issues

Open (12):
- beadster-87: add Shared folder to Xcode project
  branch: main

- beadster-82: implement session filtering
  branch: feature/sessions

Closed (33):
- beadster-86: fix compilation errors
  branch: main
  commit: abc123d
  pr: #45 (merged)
```

### issue detail with git context

```
beadster.com/issues/beadster-86

beadster-86: fix compilation errors

status: closed
priority: P0
repo: github.com/user/beadster
branch: main
commit: abc123d
pr: #45 (merged)

[View on GitHub] [View PR] [View Commit]
```

## models update

### TypeScript (API)

```typescript
// models/source.ts
export interface Source {
  id: string;
  user_id: string;
  name: string;
  type: 'local' | 'virtual' | 'inbox';
  path?: string;
  git_repo_url?: string;      // ← new
  git_repo_name?: string;     // ← new
  git_default_branch?: string; // ← new
  last_sync?: number;
  created_at: number;
  updated_at: number;
}

// models/issue.ts
export interface Issue {
  id: string;
  user_id: string;
  source_id: string;
  beads_id: string;
  title: string;
  body?: string;
  status: string;
  priority?: string;
  labels?: string[];
  git_branch?: string;        // ← new
  git_commit?: string;        // ← new
  git_pr_url?: string;        // ← new
  git_pr_number?: number;     // ← new
  created_at: number;
  updated_at: number;
  closed_at?: number;
}
```

### Swift (macOS app, sync daemon)

```swift
// Models.swift

public struct Source: Identifiable, Codable {
    public let id: String
    public let name: String
    public let type: String
    public let path: String?
    public let gitRepoUrl: String?      // ← new
    public let gitRepoName: String?     // ← new
    public let gitDefaultBranch: String? // ← new
    public var lastSync: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, path
        case gitRepoUrl = "git_repo_url"
        case gitRepoName = "git_repo_name"
        case gitDefaultBranch = "git_default_branch"
        case lastSync = "last_sync"
    }
}

public struct Issue: Identifiable, Codable {
    public let id: String
    public var title: String
    public var body: String?
    public var status: String
    public var priority: Int
    public var labels: [String]
    public var gitBranch: String?       // ← new
    public var gitCommit: String?       // ← new
    public var gitPrUrl: String?        // ← new
    public var gitPrNumber: Int?        // ← new
    public var createdAt: Int
    public var updatedAt: Int
    public var closedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, body, status, priority, labels
        case gitBranch = "git_branch"
        case gitCommit = "git_commit"
        case gitPrUrl = "git_pr_url"
        case gitPrNumber = "git_pr_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
    }
}
```

## implementation checklist

- [ ] create migration: add git fields to sources and issues tables
- [ ] update TypeScript models (Source, Issue)
- [ ] update Swift models (Source, Issue)
- [ ] update sync daemon to detect git info when syncing
- [ ] update API endpoints to accept git fields
- [ ] add GET /api/repositories endpoint
- [ ] update web app filters to support repository filtering
- [ ] add repositories page to web app
- [ ] add git context display to issue detail page
- [ ] update macOS app to show git repo info

## benefits

once implemented:
- filter all issues by repository
- see which repo each issue belongs to
- track which branch issue was created on
- link issues to PRs and commits
- support for users with multiple repos
- foundation for future GitHub integration
- better organization for teams working on multiple projects
