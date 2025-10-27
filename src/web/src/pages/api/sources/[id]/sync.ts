import type { APIContext } from 'astro';

/**
 * POST /api/sources/:id/sync - Batch sync issues from CI/CD
 * Used by GitHub Actions and other integrations
 */
export async function POST({ request, params, locals }: APIContext) {
  const { id: sourceId } = params;

  // Authenticate with API token (not session)
  const authHeader = request.headers.get('authorization');
  const token = authHeader?.replace('Bearer ', '');

  if (!token) {
    return new Response(JSON.stringify({ error: 'unauthorized - token required' }), {
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
    // Verify token
    const tokenRecord = await db.prepare(`
      SELECT id, user_id, scopes, expires_at
      FROM api_tokens
      WHERE token = ?
    `).bind(token).first();

    if (!tokenRecord) {
      return new Response(JSON.stringify({ error: 'invalid token' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Check expiration
    if (tokenRecord.expires_at && tokenRecord.expires_at < Date.now()) {
      return new Response(JSON.stringify({ error: 'token expired' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Check scopes
    const scopes = JSON.parse(tokenRecord.scopes);
    if (!scopes.includes('sync') && !scopes.includes('admin')) {
      return new Response(JSON.stringify({ error: 'insufficient permissions' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Verify source belongs to user
    const source = await db.prepare(`
      SELECT id FROM sources
      WHERE id = ? AND user_id = ?
    `).bind(sourceId, tokenRecord.user_id).first();

    if (!source) {
      return new Response(JSON.stringify({ error: 'source not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Parse issues from request body
    const body = await request.json();
    const { issues } = body;

    if (!Array.isArray(issues)) {
      return new Response(JSON.stringify({ error: 'invalid request: issues must be array' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Sync each issue
    let created = 0;
    let updated = 0;
    let skipped = 0;

    for (const issue of issues) {
      try {
        const result = await syncIssue(db, tokenRecord.user_id, sourceId, issue);
        if (result === 'created') created++;
        else if (result === 'updated') updated++;
        else skipped++;
      } catch (err) {
        console.error('failed to sync issue:', issue.id, err);
        skipped++;
      }
    }

    // Update token last_used
    await db.prepare(`
      UPDATE api_tokens SET last_used = ? WHERE id = ?
    `).bind(Date.now(), tokenRecord.id).run();

    // Log usage
    await logTokenUsage(
      db,
      tokenRecord.id,
      `/api/sources/${sourceId}/sync`,
      'POST',
      200,
      request.headers.get('cf-connecting-ip') || null,
      request.headers.get('user-agent') || null
    );

    return new Response(JSON.stringify({ created, updated, skipped }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (err) {
    console.error('sync failed:', err);
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : 'sync failed'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function syncIssue(
  db: any,
  userId: string,
  sourceId: string,
  issue: any
): Promise<'created' | 'updated' | 'skipped'> {
  // Check if issue exists by beads_id
  const existing = await db.prepare(`
    SELECT id, updated_at FROM issues
    WHERE user_id = ? AND source_id = ? AND beads_id = ?
  `).bind(userId, sourceId, issue.id).first();

  if (existing) {
    // Check if source is newer
    const sourceUpdatedAt = parseTimestamp(issue.updated_at);
    if (sourceUpdatedAt > existing.updated_at) {
      await updateIssue(db, existing.id, issue);
      return 'updated';
    } else {
      return 'skipped';
    }
  } else {
    // Create new issue
    await createIssue(db, userId, sourceId, issue);
    return 'created';
  }
}

async function createIssue(db: any, userId: string, sourceId: string, issue: any) {
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
    issue.external_ref || null,
    parseTimestamp(issue.created_at),
    parseTimestamp(issue.updated_at),
    issue.closed_at ? parseTimestamp(issue.closed_at) : null
  ).run();
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

async function logTokenUsage(
  db: any,
  tokenId: string,
  endpoint: string,
  method: string,
  status: number,
  ipAddress: string | null,
  userAgent: string | null
) {
  const usageId = `usg_${generateId()}`;
  await db.prepare(`
    INSERT INTO api_token_usage (id, token_id, endpoint, method, status, ip_address, user_agent, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    usageId,
    tokenId,
    endpoint,
    method,
    status,
    ipAddress,
    userAgent,
    Date.now()
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
