import type { APIContext } from 'astro';
import { parseGitHubUrl, createExternalRef } from '../../../lib/github';

export async function POST({ request, locals }: APIContext) {
  const user = locals.user;
  if (!user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const db = locals.runtime?.env?.DB;
  if (!db) {
    return new Response(JSON.stringify({ error: 'database not available' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const body = await request.json();
    const { repo_url, branch = 'main' } = body;

    if (!repo_url) {
      return new Response(JSON.stringify({ error: 'repo_url required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get user's GitHub access token
    const account = await db.prepare(`
      SELECT access_token FROM accounts
      WHERE user_id = ? AND provider_id = 'github'
      AND access_token IS NOT NULL
    `).bind(user.id).first();

    if (!account || !account.access_token) {
      return new Response(JSON.stringify({
        error: 'GitHub not connected. Please sign out and sign in again to grant repository access.'
      }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Parse GitHub URL
    const parsed = parseGitHubUrl(repo_url);
    if (!parsed) {
      return new Response(JSON.stringify({ error: 'invalid GitHub URL' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const { owner, repo } = parsed;

    // Fetch issues.jsonl from private repository using user's token
    const issues = await fetchPrivateBeads(owner, repo, account.access_token as string, branch);

    if (issues.length === 0) {
      return new Response(JSON.stringify({ error: 'no issues found in repository' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get or create source
    const sourceId = await getOrCreateSource(db, user.id, repo_url, `${owner}/${repo}`, branch);

    // Import each issue
    let created = 0;
    let updated = 0;
    let skipped = 0;

    for (const issue of issues) {
      try {
        const result = await importIssue(db, user.id, sourceId, issue);
        if (result === 'created') created++;
        else if (result === 'updated') updated++;
        else skipped++;
      } catch (err) {
        console.error('failed to import issue:', issue.id, err);
        skipped++;
      }
    }

    return new Response(JSON.stringify({
      success: true,
      source_id: sourceId,
      created,
      updated,
      skipped,
      total: issues.length
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err) {
    console.error('private import failed:', err);
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : 'import failed'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function fetchPrivateBeads(
  owner: string,
  repo: string,
  token: string,
  branch: string
): Promise<any[]> {
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
      throw new Error('repository not found or no .beads/issues.jsonl file');
    }
    if (response.status === 401 || response.status === 403) {
      throw new Error('access denied - check repository permissions');
    }
    throw new Error(`GitHub API error: ${response.statusText}`);
  }

  const jsonl = await response.text();
  return parseJSONL(jsonl, owner, repo);
}

function parseJSONL(jsonl: string, owner: string, repo: string): any[] {
  const lines = jsonl.split('\n').filter(line => line.trim());
  const issues: any[] = [];

  for (const line of lines) {
    try {
      const issue = JSON.parse(line);
      // Add external_ref if not present
      if (!issue.external_ref) {
        issue.external_ref = createExternalRef(owner, repo, issue.id);
      }
      issues.push(issue);
    } catch (err) {
      console.error('failed to parse JSONL line:', err);
    }
  }

  return issues;
}

async function getOrCreateSource(
  db: any,
  userId: string,
  repoUrl: string,
  repoName: string,
  branch: string
): Promise<string> {
  const existing = await db.prepare(`
    SELECT id FROM sources
    WHERE user_id = ? AND git_repo_url = ?
  `).bind(userId, repoUrl).first();

  if (existing) {
    await db.prepare(`
      UPDATE sources
      SET git_current_branch = ?, updated_at = ?
      WHERE id = ?
    `).bind(branch, Date.now(), existing.id).run();

    return existing.id;
  }

  const sourceId = `src_${generateId()}`;
  await db.prepare(`
    INSERT INTO sources (id, user_id, name, type, git_repo_url, git_current_branch, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    sourceId,
    userId,
    repoName,
    'github-import-private',
    repoUrl,
    branch,
    Date.now(),
    Date.now()
  ).run();

  return sourceId;
}

async function importIssue(
  db: any,
  userId: string,
  sourceId: string,
  issue: any
): Promise<'created' | 'updated' | 'skipped'> {
  const externalRef = issue.external_ref;

  if (externalRef) {
    const existing = await db.prepare(`
      SELECT id, updated_at FROM issues
      WHERE user_id = ? AND external_ref = ?
    `).bind(userId, externalRef).first();

    if (existing) {
      const sourceUpdatedAt = parseTimestamp(issue.updated_at);
      if (sourceUpdatedAt > existing.updated_at) {
        await updateIssue(db, existing.id, issue);
        return 'updated';
      } else {
        return 'skipped';
      }
    }
  }

  const duplicate = await db.prepare(`
    SELECT id FROM issues
    WHERE user_id = ? AND source_id = ? AND beads_id = ?
  `).bind(userId, sourceId, issue.id).first();

  if (duplicate) {
    await db.prepare(`
      UPDATE issues SET external_ref = ? WHERE id = ?
    `).bind(externalRef, duplicate.id).run();

    await updateIssue(db, duplicate.id, issue);
    return 'updated';
  }

  const issueId = `iss_${generateId()}`;
  await db.prepare(`
    INSERT INTO issues (
      id, user_id, source_id, beads_id, title, body, status, priority,
      issue_type, labels, external_ref, created_at, updated_at, closed_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    issueId,
    userId,
    sourceId,
    issue.id,
    issue.title,
    issue.body || issue.description || null,
    issue.status,
    issue.priority ?? 2,
    issue.issue_type || null,
    JSON.stringify(issue.labels || []),
    externalRef,
    parseTimestamp(issue.created_at),
    parseTimestamp(issue.updated_at),
    issue.closed_at ? parseTimestamp(issue.closed_at) : null
  ).run();

  return 'created';
}

async function updateIssue(db: any, issueId: string, issue: any) {
  await db.prepare(`
    UPDATE issues
    SET title = ?, body = ?, status = ?, priority = ?,
        issue_type = ?, labels = ?, updated_at = ?, closed_at = ?
    WHERE id = ?
  `).bind(
    issue.title,
    issue.body || issue.description || null,
    issue.status,
    issue.priority ?? 2,
    issue.issue_type || null,
    JSON.stringify(issue.labels || []),
    parseTimestamp(issue.updated_at),
    issue.closed_at ? parseTimestamp(issue.closed_at) : null,
    issueId
  ).run();
}

function parseTimestamp(dateStr: string | number): number {
  if (typeof dateStr === 'number') {
    return dateStr;
  }

  try {
    const date = new Date(dateStr);
    return Math.floor(date.getTime());
  } catch {
    return Date.now();
  }
}

function generateId(): string {
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}
