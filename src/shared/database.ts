/**
 * Shared database operations for beadster
 * Used by both web and API workers
 */

import type { D1Database } from '@cloudflare/workers-types';

export interface Issue {
  id: string;
  user_id: string;
  source_id: string;
  beads_id: string;
  title: string;
  body: string | null;
  status: string;
  priority: number | null;
  labels: string | null;
  session_id: string | null;
  client: string | null;
  project_name: string | null;
  created_at: number;
  updated_at: number;
  closed_at: number | null;
  synced_at: number | null;
}

export interface Source {
  id: string;
  user_id: string;
  name: string;
  type: string;
  path: string | null;
  last_sync: number | null;
  last_issue_number: number;
  created_at: number;
  updated_at: number;
}

export interface IssueSession {
  id: string;
  user_id: string;
  source_id: string | null;
  client: string;
  project_name: string | null;
  first_issue_at: number | null;
  last_issue_at: number | null;
  issue_count: number;
  created_at: number;
  updated_at: number;
}

/**
 * Get all issues for a user
 */
export async function getIssues(db: D1Database, userId: string, filters?: {
  status?: string;
  source_id?: string;
  session_id?: string;
  git_repo_url?: string;
}): Promise<Issue[]> {
  let query = `
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ?
  `;
  const params: any[] = [userId];

  if (filters?.status) {
    query += ' AND i.status = ?';
    params.push(filters.status);
  }

  if (filters?.source_id) {
    query += ' AND i.source_id = ?';
    params.push(filters.source_id);
  }

  if (filters?.session_id) {
    query += ' AND i.session_id = ?';
    params.push(filters.session_id);
  }

  if (filters?.git_repo_url) {
    query += ' AND i.git_repo_url = ?';
    params.push(filters.git_repo_url);
  }

  query += ' ORDER BY i.created_at DESC';

  const result = await db.prepare(query).bind(...params).all();

  return result.results.map((issue: any) => ({
    ...issue,
    labels: issue.labels ? JSON.parse(issue.labels) : []
  })) as Issue[];
}

/**
 * Get a single issue by ID
 */
export async function getIssue(db: D1Database, userId: string, issueId: string): Promise<Issue | null> {
  const result = await db.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ? AND i.id = ?
  `).bind(userId, issueId).first();

  if (!result) return null;

  return {
    ...result,
    labels: result.labels ? JSON.parse(result.labels as string) : []
  } as Issue;
}

/**
 * Get all sources/projects for a user
 */
export async function getSources(db: D1Database, userId: string): Promise<Source[]> {
  const result = await db.prepare(`
    SELECT id, name, type, last_issue_number
    FROM sources
    WHERE user_id = ?
    ORDER BY name ASC
  `).bind(userId).all();

  return result.results as Source[];
}

/**
 * Get all sessions for a user
 */
export async function getSessions(db: D1Database, userId: string, limit = 50): Promise<IssueSession[]> {
  const result = await db.prepare(`
    SELECT
      s.*,
      src.name as source_name
    FROM issue_sessions s
    LEFT JOIN sources src ON src.id = s.source_id
    WHERE s.user_id = ?
    ORDER BY s.last_issue_at DESC
    LIMIT ?
  `).bind(userId, limit).all();

  return result.results as IssueSession[];
}

/**
 * Get issues for a specific session
 */
export async function getSessionIssues(db: D1Database, userId: string, sessionId: string): Promise<Issue[]> {
  const result = await db.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ? AND i.session_id = ?
    ORDER BY i.created_at ASC
  `).bind(userId, sessionId).all();

  return result.results.map((issue: any) => ({
    ...issue,
    labels: issue.labels ? JSON.parse(issue.labels) : []
  })) as Issue[];
}

/**
 * Get label statistics
 */
export async function getLabelStats(db: D1Database, userId: string): Promise<{ label: string; count: number }[]> {
  const issues = await getIssues(db, userId);
  const labelCounts = new Map<string, number>();

  issues.forEach(issue => {
    const labels = issue.labels as any;
    if (Array.isArray(labels)) {
      labels.forEach((label: string) => {
        labelCounts.set(label, (labelCounts.get(label) || 0) + 1);
      });
    }
  });

  return Array.from(labelCounts.entries())
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count);
}

/**
 * Create a new issue
 */
export async function createIssue(
  db: D1Database,
  userId: string,
  data: {
    source_id: string;
    title: string;
    body?: string | null;
    status?: string;
    priority?: number;
  }
): Promise<{ id: string; beads_id: string }> {
  const { source_id, title, body, status, priority } = data;

  // Generate IDs
  const id = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);

  // Get source and increment issue number
  const source: any = await db.prepare(`
    SELECT id, name, last_issue_number FROM sources WHERE id = ? AND user_id = ?
  `).bind(source_id, userId).first();

  if (!source) {
    throw new Error('Source not found');
  }

  // Generate beads_id using source name as prefix
  const issueNumber = (source.last_issue_number || 0) + 1;
  const beadsId = `${source.name}-${issueNumber}`;

  // Update source's last_issue_number
  await db.prepare(`
    UPDATE sources SET last_issue_number = ?, updated_at = ? WHERE id = ?
  `).bind(issueNumber, now, source.id).run();

  const result = await db.prepare(`
    INSERT INTO issues (
      id, user_id, source_id, beads_id, title, body,
      status, priority, labels,
      synced_at, created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id,
    userId,
    source.id,
    beadsId,
    title,
    body || null,
    status || 'open',
    priority !== undefined ? String(Math.floor(priority)) : '1',
    '[]',
    now,
    now,
    now
  ).run();

  if (!result.success) {
    throw new Error('Database insert failed');
  }

  return { id, beads_id: beadsId };
}

/**
 * Update an issue
 */
export async function updateIssue(
  db: D1Database,
  userId: string,
  issueId: string,
  data: {
    title?: string;
    body?: string;
    priority?: number;
    status?: string;
  }
): Promise<void> {
  const { title, body, priority, status } = data;
  const now = Math.floor(Date.now() / 1000);

  const updates: string[] = [];
  const values: any[] = [];

  if (title !== undefined) {
    updates.push('title = ?');
    values.push(title);
  }
  if (body !== undefined) {
    updates.push('body = ?');
    values.push(body);
  }
  if (priority !== undefined) {
    updates.push('priority = ?');
    values.push(priority);
  }
  if (status !== undefined) {
    updates.push('status = ?');
    values.push(status);
    if (status === 'closed') {
      updates.push('closed_at = ?');
      values.push(now);
    }
  }

  updates.push('updated_at = ?');
  values.push(now);
  values.push(issueId);
  values.push(userId);

  await db.prepare(`
    UPDATE issues
    SET ${updates.join(', ')}
    WHERE id = ? AND user_id = ?
  `).bind(...values).run();
}

/**
 * Close an issue
 */
export async function closeIssue(db: D1Database, userId: string, issueId: string): Promise<void> {
  const now = Math.floor(Date.now() / 1000);

  await db.prepare(`
    UPDATE issues
    SET status = ?, closed_at = ?, updated_at = ?
    WHERE id = ? AND user_id = ?
  `).bind('closed', now, now, issueId, userId).run();
}

/**
 * Get sources with issue counts for a user
 */
export async function getSourcesWithStats(db: D1Database, userId: string): Promise<any[]> {
  const result = await db.prepare(`
    SELECT
      s.id,
      s.name,
      s.type,
      s.path,
      s.last_issue_number,
      s.last_sync,
      s.created_at,
      COUNT(i.id) as issue_count,
      SUM(CASE WHEN i.status = 'open' THEN 1 ELSE 0 END) as open_count
    FROM sources s
    LEFT JOIN issues i ON i.source_id = s.id
    WHERE s.user_id = ?
    GROUP BY s.id
    ORDER BY s.name ASC
  `).bind(userId).all();

  return result.results || [];
}

/**
 * Get issues grouped by label
 */
export async function getIssuesByLabel(db: D1Database, userId: string): Promise<Map<string, any[]>> {
  const result = await db.prepare(
    'SELECT id, beads_id, title, status, labels FROM issues WHERE user_id = ? AND status = ? ORDER BY beads_id'
  ).bind(userId, 'open').all();

  const issues = result.results as any[];
  const labelGroups = new Map<string, any[]>();

  // Group by labels
  for (const issue of issues) {
    if (!issue.labels) continue;

    const labels = JSON.parse(issue.labels) as string[];

    // Skip system labels
    const userLabels = labels.filter((l: string) => !l.startsWith('-x-'));

    if (userLabels.length === 0) {
      if (!labelGroups.has('no labels')) {
        labelGroups.set('no labels', []);
      }
      labelGroups.get('no labels')!.push(issue);
    } else {
      for (const label of userLabels) {
        if (!labelGroups.has(label)) {
          labelGroups.set(label, []);
        }
        labelGroups.get(label)!.push(issue);
      }
    }
  }

  return labelGroups;
}

/**
 * Get repositories with issue counts
 */
export async function getRepositories(db: D1Database, userId: string): Promise<any[]> {
  const result = await db.prepare(`
    SELECT
      git_repo_url,
      COUNT(*) as total_issues,
      SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) as open_issues,
      SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END) as closed_issues,
      MAX(updated_at) as latest_activity
    FROM issues
    WHERE user_id = ? AND git_repo_url IS NOT NULL AND git_repo_url != ''
    GROUP BY git_repo_url
    ORDER BY latest_activity DESC
  `).bind(userId).all();

  return result.results || [];
}

/**
 * Get statistics for a user
 */
export async function getUserStats(db: D1Database, userId: string): Promise<{
  total_issues: number;
  open_issues: number;
  closed_issues: number;
  total_sources: number;
  total_sessions: number;
  issues_by_priority: { priority: number; count: number }[];
  issues_by_source: { source_name: string; count: number }[];
  recent_activity: { date: string; count: number }[];
}> {
  // Total issues
  const totalResult = await db.prepare('SELECT COUNT(*) as count FROM issues WHERE user_id = ?').bind(userId).first();
  const total_issues = totalResult?.count || 0;

  // Open/closed
  const openResult = await db.prepare('SELECT COUNT(*) as count FROM issues WHERE user_id = ? AND status = ?').bind(userId, 'open').first();
  const open_issues = openResult?.count || 0;

  const closedResult = await db.prepare('SELECT COUNT(*) as count FROM issues WHERE user_id = ? AND status = ?').bind(userId, 'closed').first();
  const closed_issues = closedResult?.count || 0;

  // Sources
  const sourcesResult = await db.prepare('SELECT COUNT(*) as count FROM sources WHERE user_id = ?').bind(userId).first();
  const total_sources = sourcesResult?.count || 0;

  // Sessions
  const sessionsResult = await db.prepare('SELECT COUNT(*) as count FROM issue_sessions WHERE user_id = ?').bind(userId).first();
  const total_sessions = sessionsResult?.count || 0;

  // By priority
  const priorityResults = await db.prepare(
    'SELECT priority, COUNT(*) as count FROM issues WHERE user_id = ? AND priority IS NOT NULL GROUP BY priority ORDER BY priority'
  ).bind(userId).all();
  const issues_by_priority = priorityResults.results as { priority: number; count: number }[];

  // By source
  const sourceResults = await db.prepare(`
    SELECT s.name as source_name, COUNT(i.id) as count
    FROM sources s
    INNER JOIN issues i ON i.source_id = s.id
    WHERE s.user_id = ? AND i.user_id = ?
    GROUP BY s.id, s.name
    ORDER BY count DESC
  `).bind(userId, userId).all();
  const issues_by_source = sourceResults.results as { source_name: string; count: number }[];

  // Recent activity (last 7 days)
  const activityResults = await db.prepare(`
    SELECT DATE(created_at, 'unixepoch') as date, COUNT(*) as count
    FROM issues
    WHERE user_id = ? AND created_at > ?
    GROUP BY date
    ORDER BY date DESC
    LIMIT 7
  `).bind(userId, Math.floor(Date.now() / 1000) - 7 * 24 * 60 * 60).all();
  const recent_activity = activityResults.results as { date: string; count: number }[];

  return {
    total_issues,
    open_issues,
    closed_issues,
    total_sources,
    total_sessions,
    issues_by_priority,
    issues_by_source,
    recent_activity
  };
}
