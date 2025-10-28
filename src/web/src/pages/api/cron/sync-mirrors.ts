import type { APIContext } from 'astro';
import { fetchPublicBeads } from '../../../lib/github';

export async function GET({ locals, request }: APIContext) {
  // Verify this is a Cloudflare cron request
  const cronHeader = request.headers.get('cf-cron');
  if (!cronHeader) {
    return new Response(JSON.stringify({ error: 'unauthorized - not a cron request' }), {
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
    // Get all sources that need syncing
    const now = Date.now();
    const sources = await db.prepare(`
      SELECT * FROM sources
      WHERE auto_sync = 1
        AND is_mirror = 1
        AND type = 'github-mirror'
        AND (last_sync IS NULL OR last_sync < ?)
    `).bind(now - (5 * 60 * 1000)).all(); // sources not synced in last 5 minutes

    console.log(`syncing ${sources.results?.length || 0} mirrors`);

    const results = [];

    for (const source of sources.results || []) {
      try {
        const result = await syncSource(db, source);
        results.push(result);
      } catch (err) {
        console.error(`failed to sync source ${source.id}:`, err);
        results.push({
          source_id: source.id,
          error: err instanceof Error ? err.message : String(err)
        });
      }
    }

    return new Response(JSON.stringify({
      success: true,
      synced: results.length,
      results
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err) {
    console.error('mirror sync failed:', err);
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : 'sync failed'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function syncSource(db: any, source: any) {
  // Parse repo URL
  const match = source.git_repo_url?.match(/github\.com[\/:]([^\/]+)\/([^\/\.]+)/);
  if (!match) {
    throw new Error(`invalid repo URL: ${source.git_repo_url}`);
  }

  const owner = match[1];
  const repo = match[2];
  const branch = source.git_current_branch || 'main';

  // Fetch latest issues from GitHub
  const issues = await fetchPublicBeads(owner, repo, branch);

  let created = 0;
  let updated = 0;
  let skipped = 0;

  for (const issue of issues) {
    try {
      const result = await syncIssue(db, source.user_id, source.id, issue);
      if (result === 'created') created++;
      else if (result === 'updated') updated++;
      else skipped++;
    } catch (err) {
      console.error('failed to sync issue:', issue.id, err);
      skipped++;
    }
  }

  // Update last_sync timestamp
  await db.prepare(`
    UPDATE sources SET last_sync = ?, updated_at = ? WHERE id = ?
  `).bind(Date.now(), Date.now(), source.id).run();

  console.log(`synced ${source.name}: ${created} created, ${updated} updated, ${skipped} skipped`);

  return {
    source_id: source.id,
    name: source.name,
    created,
    updated,
    skipped,
    total: issues.length
  };
}

async function syncIssue(
  db: any,
  userId: string,
  sourceId: string,
  issue: any
): Promise<'created' | 'updated' | 'skipped'> {
  const externalRef = issue.external_ref;

  // Check for existing issue by external_ref
  if (externalRef) {
    const existing = await db.prepare(`
      SELECT id, updated_at FROM issues
      WHERE user_id = ? AND external_ref = ?
    `).bind(userId, externalRef).first();

    if (existing) {
      // Check if source issue is newer
      const sourceUpdatedAt = parseTimestamp(issue.updated_at);
      if (sourceUpdatedAt > existing.updated_at) {
        await updateIssue(db, existing.id, issue);
        return 'updated';
      } else {
        return 'skipped';
      }
    }
  }

  // Check for duplicate by beads_id
  const duplicate = await db.prepare(`
    SELECT id FROM issues
    WHERE user_id = ? AND source_id = ? AND beads_id = ?
  `).bind(userId, sourceId, issue.id).first();

  if (duplicate) {
    // Set external_ref and update
    if (externalRef) {
      await db.prepare(`
        UPDATE issues SET external_ref = ? WHERE id = ?
      `).bind(externalRef, duplicate.id).run();
    }

    await updateIssue(db, duplicate.id, issue);
    return 'updated';
  }

  // Create new issue
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
  if (typeof dateStr === 'number') return dateStr;
  try {
    return Math.floor(new Date(dateStr).getTime());
  } catch {
    return Date.now();
  }
}

function generateId(): string {
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}
