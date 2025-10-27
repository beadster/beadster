# GitHub import implementation plan

detailed plan for implementing GitHub repository import in beadster web app

## overview

enable users to import any GitHub repository that uses beads by:
- pasting GitHub repo URL
- fetching `.beads/issues.jsonl` from GitHub
- parsing and importing issues into beadster cloud
- matching by external_ref to prevent duplicates

## phases

### phase 1: external_ref foundation
- add external_ref to database schema
- update API to handle external_ref
- update models and types
- add indexes for performance

### phase 2: GitHub API integration
- implement GitHub raw file fetching
- support both public and private repos
- handle authentication with OAuth tokens
- implement error handling and retries

### phase 3: import UI
- create import page
- add form for repo URL and branch
- show import progress
- display results and errors

### phase 4: matching and deduplication
- implement external_ref matching logic
- smart merge of existing issues
- handle conflicts and updates
- track import history

## detailed implementation

### 1. database schema changes

```sql
-- add external_ref to issues table
ALTER TABLE issues ADD COLUMN external_ref TEXT;

-- create index for fast lookups
CREATE INDEX idx_issues_external_ref ON issues(external_ref);

-- add import tracking table
CREATE TABLE imports (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  repo_url TEXT NOT NULL,
  branch TEXT NOT NULL DEFAULT 'main',
  status TEXT NOT NULL, -- 'pending', 'in_progress', 'completed', 'failed'
  issues_created INTEGER DEFAULT 0,
  issues_updated INTEGER DEFAULT 0,
  issues_skipped INTEGER DEFAULT 0,
  error_message TEXT,
  started_at INTEGER NOT NULL,
  completed_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id)
);

CREATE INDEX idx_imports_user ON imports(user_id);
CREATE INDEX idx_imports_source ON imports(source_id);
```

### 2. API endpoints

#### POST /api/import/github

start GitHub import

request:
```json
{
  "repo_url": "https://github.com/owner/repo",
  "branch": "main",
  "source_name": "optional-name"
}
```

response:
```json
{
  "import_id": "imp_xxxxxx",
  "status": "pending"
}
```

#### GET /api/import/:import_id/status

check import status

response:
```json
{
  "id": "imp_xxxxxx",
  "status": "completed",
  "created": 45,
  "updated": 2,
  "skipped": 0
}
```

#### GET /api/import/history

list user's import history

response:
```json
{
  "imports": [
    {
      "id": "imp_xxxxxx",
      "repo_url": "https://github.com/owner/repo",
      "created": 45,
      "status": "completed",
      "completed_at": 1234567890
    }
  ]
}
```

### 3. external_ref format

standard: `github:{owner}/{repo}:{issue_id}`

examples:
- `github:steveyegge/beads:bd-1`
- `github:systemoperator/beadster:beadster-42`

parsing logic:
```typescript
function parseExternalRef(ref: string) {
  const match = ref.match(/^github:([^:]+):(.+)$/);
  if (!match) return null;

  const [, repoPath, issueId] = match;
  return { platform: 'github', repoPath, issueId };
}

function createExternalRef(repoUrl: string, issueId: string) {
  const match = repoUrl.match(/github\.com[\/:]([^\/]+\/[^\/\.]+)/);
  if (!match) throw new Error('invalid GitHub URL');

  const repoPath = match[1];
  return `github:${repoPath}:${issueId}`;
}
```

### 4. GitHub API integration

#### fetch issues.jsonl from public repo

```typescript
async function fetchPublicBeads(owner: string, repo: string, branch: string = 'main') {
  const url = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/.beads/issues.jsonl`;

  const response = await fetch(url);
  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('repository not found or no .beads/issues.jsonl');
    }
    throw new Error(`GitHub API error: ${response.statusText}`);
  }

  return await response.text();
}
```

#### fetch from private repo (with OAuth token)

```typescript
async function fetchPrivateBeads(owner: string, repo: string, token: string, branch: string = 'main') {
  // use GitHub API (requires authentication)
  const url = `https://api.github.com/repos/${owner}/${repo}/contents/.beads/issues.jsonl?ref=${branch}`;

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github.v3.raw',
      'User-Agent': 'Beadster-Import'
    }
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('repository not found or no .beads/issues.jsonl');
    }
    if (response.status === 401 || response.status === 403) {
      throw new Error('authentication failed - check GitHub token');
    }
    throw new Error(`GitHub API error: ${response.statusText}`);
  }

  return await response.text();
}
```

### 5. import processing logic

```typescript
async function processImport(
  db: D1Database,
  importId: string,
  userId: string,
  repoUrl: string,
  branch: string,
  githubToken?: string
) {
  // update status to in_progress
  await db.prepare(`
    UPDATE imports SET status = 'in_progress'
    WHERE id = ?
  `).bind(importId).run();

  try {
    // extract owner/repo from URL
    const { owner, repo } = parseGitHubUrl(repoUrl);

    // fetch issues.jsonl
    const jsonl = githubToken
      ? await fetchPrivateBeads(owner, repo, githubToken, branch)
      : await fetchPublicBeads(owner, repo, branch);

    // create or get source
    const sourceId = await getOrCreateSource(db, userId, repoUrl, repo);

    // parse and import issues
    const lines = jsonl.split('\n').filter(line => line.trim());
    let created = 0, updated = 0, skipped = 0;

    for (const line of lines) {
      try {
        const issue = JSON.parse(line);
        const result = await importIssue(db, userId, sourceId, issue, repoUrl);

        if (result === 'created') created++;
        else if (result === 'updated') updated++;
        else skipped++;
      } catch (err) {
        console.error('failed to import issue:', err);
        skipped++;
      }
    }

    // update import record
    await db.prepare(`
      UPDATE imports
      SET status = 'completed',
          issues_created = ?,
          issues_updated = ?,
          issues_skipped = ?,
          completed_at = ?
      WHERE id = ?
    `).bind(created, updated, skipped, Date.now(), importId).run();

  } catch (error) {
    // update import record with error
    await db.prepare(`
      UPDATE imports
      SET status = 'failed',
          error_message = ?,
          completed_at = ?
      WHERE id = ?
    `).bind(error.message, Date.now(), importId).run();

    throw error;
  }
}

async function importIssue(
  db: D1Database,
  userId: string,
  sourceId: string,
  issue: any,
  repoUrl: string
): Promise<'created' | 'updated' | 'skipped'> {
  const externalRef = createExternalRef(repoUrl, issue.id);

  // check for existing issue by external_ref
  const existing = await db.prepare(`
    SELECT id, updated_at FROM issues
    WHERE user_id = ? AND external_ref = ?
  `).bind(userId, externalRef).first();

  if (existing) {
    // check if source issue is newer
    const sourceUpdatedAt = parseTimestamp(issue.updated_at);
    if (sourceUpdatedAt > existing.updated_at) {
      // update existing
      await updateIssueFromImport(db, existing.id, issue);
      return 'updated';
    } else {
      return 'skipped';
    }
  } else {
    // check for duplicate by beads_id (in case external_ref wasn't set)
    const duplicate = await db.prepare(`
      SELECT id FROM issues
      WHERE user_id = ? AND source_id = ? AND beads_id = ?
    `).bind(userId, sourceId, issue.id).first();

    if (duplicate) {
      // update existing with external_ref
      await db.prepare(`
        UPDATE issues SET external_ref = ? WHERE id = ?
      `).bind(externalRef, duplicate.id).run();

      await updateIssueFromImport(db, duplicate.id, issue);
      return 'updated';
    } else {
      // create new with external_ref
      await createIssueFromImport(db, userId, sourceId, issue, externalRef);
      return 'created';
    }
  }
}
```

### 6. UI implementation

create `/src/web/src/pages/import.astro`:

```astro
---
import Layout from '../layouts/Layout.astro';

if (!Astro.locals.user) {
  return Astro.redirect('/login');
}

let error = null;
let success = null;

if (Astro.request.method === 'POST') {
  const formData = await Astro.request.formData();
  const repoUrl = formData.get('repo_url');
  const branch = formData.get('branch') || 'main';

  if (repoUrl) {
    try {
      // call import API
      const response = await fetch('/api/import/github', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ repo_url: repoUrl, branch })
      });

      if (response.ok) {
        const result = await response.json();
        success = `import started: ${result.import_id}`;
      } else {
        error = 'import failed - check repository URL';
      }
    } catch (e) {
      error = `error: ${e.message}`;
    }
  }
}
---

<Layout title="import from GitHub">
  <nav class="tabs">
    <a href="/">open</a>
    <a href="/sources">sources</a>
    <a href="/import" class="active">import</a>
  </nav>

  <h2>import from GitHub</h2>

  {error && <div class="error">{error}</div>}
  {success && <div class="success">{success}</div>}

  <form method="post" class="import-form">
    <div class="form-group">
      <label for="repo_url">GitHub repository URL</label>
      <input
        type="text"
        id="repo_url"
        name="repo_url"
        placeholder="https://github.com/owner/repo"
        required
      />
      <small>must contain .beads/issues.jsonl</small>
    </div>

    <div class="form-group">
      <label for="branch">branch (optional)</label>
      <input
        type="text"
        id="branch"
        name="branch"
        value="main"
      />
    </div>

    <button type="submit">import</button>
  </form>

  <div class="help">
    <h3>how it works</h3>
    <ul>
      <li>paste GitHub repository URL</li>
      <li>we fetch .beads/issues.jsonl</li>
      <li>issues are imported to your beadster cloud</li>
      <li>duplicates are detected by external_ref</li>
    </ul>
  </div>
</Layout>

<style>
  .import-form {
    max-width: 600px;
    margin: 20px 0;
  }

  .form-group {
    margin-bottom: 20px;
  }

  label {
    display: block;
    margin-bottom: 5px;
    font-weight: 500;
  }

  input[type="text"] {
    width: 100%;
    padding: 10px;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    font-size: 14px;
  }

  small {
    display: block;
    margin-top: 5px;
    color: var(--text-secondary);
    font-size: 12px;
  }

  button {
    padding: 10px 20px;
    background: var(--primary-color);
    color: white;
    border: none;
    border-radius: 4px;
    font-size: 14px;
    cursor: pointer;
  }

  .help {
    margin-top: 40px;
    padding: 20px;
    background: var(--bg-secondary);
    border-radius: 4px;
  }

  .help h3 {
    margin-top: 0;
  }

  .help ul {
    margin: 0;
    padding-left: 20px;
  }

  .help li {
    margin-bottom: 8px;
  }

  .error {
    padding: 10px;
    background: #fee;
    color: #c00;
    border-radius: 4px;
    margin-bottom: 20px;
  }

  .success {
    padding: 10px;
    background: #efe;
    color: #060;
    border-radius: 4px;
    margin-bottom: 20px;
  }
</style>
```

### 7. testing strategy

#### test cases

1. **public repo import**
   - happy path: import steveyegge/beads
   - verify all issues imported
   - verify external_ref set correctly

2. **private repo import**
   - with valid GitHub token
   - with invalid token (should fail gracefully)
   - without token (should fail with clear message)

3. **duplicate detection**
   - import same repo twice
   - verify no duplicates created
   - verify updated_at compared correctly

4. **error handling**
   - repo doesn't exist (404)
   - repo has no .beads directory (404)
   - malformed JSONL
   - network timeout
   - rate limiting

5. **edge cases**
   - empty issues.jsonl
   - very large issues.jsonl (>1000 issues)
   - invalid issue format
   - missing required fields

#### manual testing

```bash
# test with beads repo
curl -X POST http://localhost:8788/api/import/github \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"repo_url": "https://github.com/steveyegge/beads", "branch": "main"}'

# check status
curl http://localhost:8788/api/import/imp_xxxxx/status \
  -H "Authorization: Bearer $TOKEN"
```

## deployment checklist

- [ ] run database migration to add external_ref column
- [ ] add external_ref index
- [ ] create imports table
- [ ] deploy API endpoints
- [ ] deploy import page
- [ ] test with public repo
- [ ] test with private repo
- [ ] update documentation
- [ ] add to navigation menu

## future enhancements

- scheduled re-imports (keep in sync)
- GitLab support
- Bitbucket support
- import from URL (any git hosting)
- bulk import (multiple repos)
- webhook support (auto-import on push)
- conflict resolution UI
- import history and rollback
