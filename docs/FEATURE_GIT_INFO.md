# git integration

tracking git context for issues

## database fields

```sql
ALTER TABLE issues ADD COLUMN git_repo TEXT;       -- "https://github.com/user/repo"
ALTER TABLE issues ADD COLUMN git_branch TEXT;     -- "feature/auth"
ALTER TABLE issues ADD COLUMN git_commit TEXT;     -- commit SHA when work done
ALTER TABLE issues ADD COLUMN git_pr_url TEXT;     -- "https://github.com/user/repo/pull/123"
ALTER TABLE issues ADD COLUMN git_pr_number TEXT;  -- "123"
```

## use cases

### 1. auto-capture from mcp

when agent creates issue, capture current git context:

```typescript
async function createIssue(title: string) {
  const gitInfo = await getGitInfo();

  const issue = {
    title,
    git_repo: gitInfo.remoteUrl,      // from git remote get-url origin
    git_branch: gitInfo.currentBranch, // from git branch --show-current
    git_commit: null                   // set when closing
  };

  return await db.insert(issue);
}

async function getGitInfo() {
  const remoteUrl = execSync('git remote get-url origin').toString().trim();
  const currentBranch = execSync('git branch --show-current').toString().trim();

  return { remoteUrl, currentBranch };
}
```

### 2. link pr when created

```typescript
// when creating PR, update issue
async function linkPR(issueId: string, prUrl: string) {
  const prNumber = prUrl.match(/\/pull\/(\d+)/)?.[1];

  await db.update(issueId, {
    git_pr_url: prUrl,
    git_pr_number: prNumber,
    status: 'in_review'
  });
}
```

### 3. close from git commit

git hook to auto-close issues:

```bash
#!/bin/bash
# .git/hooks/commit-msg

COMMIT_MSG=$(cat $1)
COMMIT_SHA=$(git rev-parse HEAD)

# check for "fixes bd-123" or "closes bd-456" in commit message
if [[ $COMMIT_MSG =~ (fixes|closes|resolves)\s+(bd-[0-9]+) ]]; then
  ISSUE_ID="${BASH_REMATCH[2]}"

  # call beadster api to close issue
  curl -X PATCH "https://api.beadster.com/api/issues/$ISSUE_ID" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{
      \"status\": \"closed\",
      \"git_commit\": \"$COMMIT_SHA\",
      \"close_reason\": \"fixed in commit $COMMIT_SHA\"
    }"
fi
```

example commit message:
```
fix auth timeout issue

fixes bd-42
```

result: bd-42 automatically closed with git_commit set

### 4. filter issues by branch

```sql
-- get all issues for current feature branch
SELECT * FROM issues
WHERE git_branch = 'feature/auth'
ORDER BY created_at DESC;
```

### 5. track which commits fixed which issues

```sql
-- see what was fixed in this commit
SELECT id, title, git_commit
FROM issues
WHERE git_commit = 'abc123def456'
ORDER BY closed_at DESC;
```

## mcp tools

```typescript
tools: [
  'git_link_pr',      // link PR to issue
  'git_close_issue',  // close issue with commit SHA
  'git_branch_issues' // list issues for current branch
]
```

## api endpoints

```typescript
// link PR
PATCH /api/issues/:id/git
{
  "pr_url": "https://github.com/user/repo/pull/123"
}

// close with commit
POST /api/issues/:id/close
{
  "commit": "abc123def456",
  "reason": "fixed in this commit"
}

// filter by branch
GET /api/issues?git_branch=feature/auth
```

## ui views

### issue detail

```
bd-42: fix auth timeout

status: closed
priority: P0
branch: feature/auth
pr: #123 (merged)
commit: abc123d
closed: 2 hours ago by anton

[view on github] [view pr] [view commit]
```

### branch view

```
beadster.com/git/branches/feature/auth

issues on branch: feature/auth

open (2):
- bd-45: add oauth providers
- bd-47: improve error messages

closed (3):
- bd-42: fix auth timeout (commit: abc123d)
- bd-43: add rate limiting (commit: def456a)
- bd-44: update tests (commit: 789beef)
```

### pr integration

```
beadster.com/issues/bd-42

linked pr: #123 (merged)

commits in pr:
- abc123d: fix timeout logic
- def456a: add tests
- 789beef: update docs

files changed: 5
+120 -45
```

## github integration

optional: use github api to enrich data

```typescript
async function enrichWithGithub(issue) {
  if (!issue.git_pr_url) return issue;

  // fetch pr data from github api
  const pr = await github.pulls.get({
    owner: 'user',
    repo: 'repo',
    pull_number: issue.git_pr_number
  });

  return {
    ...issue,
    pr_status: pr.state,        // open/closed/merged
    pr_merged_at: pr.merged_at,
    pr_files_changed: pr.changed_files,
    pr_additions: pr.additions,
    pr_deletions: pr.deletions
  };
}
```

## sync daemon changes

detect git info when syncing:

```swift
func syncIssueToCloud(issue: Issue) async throws {
  let gitInfo = getGitInfo()

  let enriched = Issue(
    id: issue.id,
    title: issue.title,
    // ... other fields
    gitRepo: gitInfo.remoteUrl,
    gitBranch: gitInfo.currentBranch,
    gitCommit: issue.gitCommit
  )

  await cloudAPI.upsertIssue(enriched)
}

func getGitInfo() -> GitInfo {
  let remoteUrl = shell("git remote get-url origin")
  let currentBranch = shell("git branch --show-current")

  return GitInfo(
    remoteUrl: remoteUrl,
    currentBranch: currentBranch
  )
}
```

## benefits

- see which branch an issue belongs to
- know which pr fixed which issue
- filter work by branch
- auto-close from commits
- track code changes linked to issues
- full traceability: issue → pr → commit
