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
  priority: string | null;
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
