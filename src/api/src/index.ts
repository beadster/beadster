import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { ulid } from 'ulid';
import { createAuth } from './lib/auth';
import type { Auth } from './lib/auth';

type Bindings = {
  DB: D1Database;
  ENVIRONMENT: string;
  BASE_URL: string;
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  BETTER_AUTH_SECRET: string;
};

type Variables = {
  auth: Auth;
  user: any | null;
};

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// CORS
app.use('/*', cors());

// Initialize Better Auth
app.use('/*', async (c, next) => {
  const auth = createAuth(
    c.env.DB,
    c.env.BETTER_AUTH_SECRET,
    c.env.BASE_URL,
    c.env.GITHUB_CLIENT_ID,
    c.env.GITHUB_CLIENT_SECRET
  );
  c.set('auth', auth);
  await next();
});

// Better Auth routes
app.use('/v1/auth/*', async (c) => {
  const auth = c.get('auth');
  return await auth.handler(c.req.raw);
});

// Get current user info
app.get('/v1/auth/me', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  return c.json({ user });
});

// Health check
app.get('/', (c) => {
  return c.json({
    name: 'beadster-api',
    version: '0.1.0',
    status: 'ok'
  });
});

// Auth: Register/Get API key (for PoC)
app.post('/v1/auth/register', async (c) => {
  const { email } = await c.req.json();

  if (!email) {
    return c.json({ error: 'Email required' }, 400);
  }

  const userId = crypto.randomUUID();
  const apiKey = crypto.randomUUID();
  const now = Date.now();

  try {
    await c.env.DB.prepare(`
      INSERT INTO users (id, email, api_key, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(userId, email, apiKey, now, now).run();

    return c.json({
      user_id: userId,
      email,
      api_key: apiKey
    });
  } catch (error) {
    // User might already exist
    const existing = await c.env.DB.prepare(`
      SELECT id, email, api_key FROM users WHERE email = ?
    `).bind(email).first();

    if (existing) {
      return c.json({
        user_id: existing.id,
        email: existing.email,
        api_key: existing.api_key
      });
    }

    return c.json({ error: 'Registration failed' }, 500);
  }
});

// Sync: Push issues from daemon
app.post('/v1/sync/push', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { source, issues, device_id, client } = await c.req.json();
  console.log('Push request:', JSON.stringify({ source, issueCount: issues.length, firstIssue: issues[0] }));

  const syncLogId = ulid();
  const startTime = Date.now();
  const now = startTime;

  let createdCount = 0;
  let updatedCount = 0;
  const issueIds: string[] = [];

  try {
    // Upsert source
    await c.env.DB.prepare(`
      INSERT INTO sources (id, user_id, name, type, path, git_repo_url, git_current_branch, last_sync, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        git_repo_url = excluded.git_repo_url,
        git_current_branch = excluded.git_current_branch,
        last_sync = excluded.last_sync,
        updated_at = excluded.updated_at
    `).bind(
      source.id,
      user.id,
      source.name,
      source.type || 'local',
      source.path,
      source.git_repo_url || null,
      source.git_current_branch || null,
      now,
      now,
      now
    ).run();

    // Upsert issues
    for (const issue of issues) {
      issueIds.push(issue.id);

      // First, check if issue exists by beads_id
      const existing = await c.env.DB.prepare(`
        SELECT id FROM issues WHERE source_id = ? AND beads_id = ?
      `).bind(source.id, issue.beads_id).first();

      if (existing) {
        // Update existing issue
        await c.env.DB.prepare(`
          UPDATE issues SET
            title = ?,
            body = ?,
            status = ?,
            priority = ?,
            labels = ?,
            session_id = ?,
            client = ?,
            project_name = ?,
            synced_at = ?,
            updated_at = ?
          WHERE source_id = ? AND beads_id = ?
        `).bind(
          issue.title,
          issue.body || null,
          issue.status,
          issue.priority || null,
          JSON.stringify(issue.labels || []),
          issue.session_id || null,
          issue.client || null,
          issue.project_name || null,
          now,
          issue.updated_at,
          source.id,
          issue.beads_id
        ).run();
        updatedCount++;
      } else {
        // Insert new issue
        await c.env.DB.prepare(`
          INSERT INTO issues (
            id, user_id, source_id, beads_id, title, body,
            status, priority, labels,
            session_id, client, project_name,
            git_repo_url, git_branch, git_commit_hash, git_is_dirty,
            synced_at, created_at, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).bind(
          issue.id,
          user.id,
          source.id,
          issue.beads_id,
          issue.title,
          issue.body || null,
          issue.status,
          issue.priority || null,
          JSON.stringify(issue.labels || []),
          issue.session_id || null,
          issue.client || null,
          issue.project_name || null,
          issue.git_repo_url || null,
          issue.git_branch || null,
          issue.git_commit_hash || null,
          issue.git_is_dirty ? 1 : 0,
          now,
          issue.created_at,
          issue.updated_at
        ).run();
        createdCount++;
      }

      // Update session tracking
      if (issue.session_id) {
        await c.env.DB.prepare(`
          INSERT INTO issue_sessions (
            id, user_id, source_id, client, project_name,
            first_issue_at, last_issue_at, issue_count,
            created_at, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            last_issue_at = excluded.last_issue_at,
            issue_count = issue_count + 1,
            updated_at = excluded.updated_at
        `).bind(
          issue.session_id,
          user.id,
          source.id,
          issue.client || 'unknown',
          issue.project_name || null,
          issue.created_at,
          issue.created_at,
          now,
          now
        ).run();
      }
    }

    const completedAt = Date.now();
    const duration = completedAt - startTime;

    // Log successful sync
    await c.env.DB.prepare(`
      INSERT INTO sync_logs (
        id, user_id, source_id, device_id,
        operation, direction, client,
        issue_count, issues_created, issues_updated,
        issue_ids, status, duration_ms,
        started_at, completed_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      syncLogId,
      user.id,
      source.id,
      device_id || null,
      'push',
      'up',
      client || null,
      issues.length,
      createdCount,
      updatedCount,
      JSON.stringify(issueIds),
      'success',
      duration,
      startTime,
      completedAt,
      completedAt
    ).run();

    return c.json({ synced: issues.length, sync_log_id: syncLogId });
  } catch (error: any) {
    const completedAt = Date.now();
    const duration = completedAt - startTime;

    // Log failed sync
    await c.env.DB.prepare(`
      INSERT INTO sync_logs (
        id, user_id, source_id, device_id,
        operation, direction, client,
        issue_count, status, error_message, error_code,
        duration_ms, started_at, completed_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      syncLogId,
      user.id,
      source.id,
      device_id || null,
      'push',
      'up',
      client || null,
      issues.length,
      'failed',
      error.message || 'Unknown error',
      error.code || null,
      duration,
      startTime,
      completedAt,
      completedAt
    ).run();

    throw error;
  }
});

// Sync: Pull changes from cloud
app.get('/v1/sync/pull', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sourceId = c.req.query('source_id');
  const since = parseInt(c.req.query('since') || '0');
  const deviceId = c.req.query('device_id');
  const client = c.req.query('client');

  if (!sourceId) {
    return c.json({ error: 'source_id required' }, 400);
  }

  const syncLogId = ulid();
  const startTime = Date.now();

  try {
    const changes = await c.env.DB.prepare(`
      SELECT * FROM issues
      WHERE source_id = ? AND user_id = ? AND updated_at > ?
      ORDER BY updated_at ASC
    `).bind(sourceId, user.id, since).all();

    // Parse labels JSON for each issue
    const parsedIssues = changes.results.map((issue: any) => ({
      ...issue,
      labels: issue.labels ? JSON.parse(issue.labels) : []
    }));

    const completedAt = Date.now();
    const duration = completedAt - startTime;
    const issueIds = parsedIssues.map((issue: any) => issue.id);

    // Log successful pull
    await c.env.DB.prepare(`
      INSERT INTO sync_logs (
        id, user_id, source_id, device_id,
        operation, direction, client,
        issue_count, issue_ids, status, duration_ms,
        started_at, completed_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      syncLogId,
      user.id,
      sourceId,
      deviceId || null,
      'pull',
      'down',
      client || null,
      parsedIssues.length,
      JSON.stringify(issueIds),
      'success',
      duration,
      startTime,
      completedAt,
      completedAt
    ).run();

    return c.json(parsedIssues);
  } catch (error: any) {
    const completedAt = Date.now();
    const duration = completedAt - startTime;

    // Log failed pull
    await c.env.DB.prepare(`
      INSERT INTO sync_logs (
        id, user_id, source_id, device_id,
        operation, direction, client,
        status, error_message, error_code,
        duration_ms, started_at, completed_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      syncLogId,
      user.id,
      sourceId,
      deviceId || null,
      'pull',
      'down',
      client || null,
      'failed',
      error.message || 'Unknown error',
      error.code || null,
      duration,
      startTime,
      completedAt,
      completedAt
    ).run();

    throw error;
  }
});

// Web: List all issues
app.get('/v1/issues', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  // Query parameters for filtering
  const repoUrl = c.req.query('repo');
  const status = c.req.query('status');
  const sourceId = c.req.query('source_id');
  const beadsId = c.req.query('beads_id');

  // Build dynamic query
  let whereClause = 'WHERE i.user_id = ?';
  const params: any[] = [user.id];

  if (repoUrl) {
    whereClause += ' AND i.git_repo_url = ?';
    params.push(repoUrl);
  }

  if (status) {
    whereClause += ' AND i.status = ?';
    params.push(status);
  }

  if (sourceId) {
    whereClause += ' AND i.source_id = ?';
    params.push(sourceId);
  }

  if (beadsId) {
    whereClause += ' AND i.beads_id = ?';
    params.push(beadsId);
  }

  const issues = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    ${whereClause}
    ORDER BY i.created_at DESC
  `).bind(...params).all();

  // Parse labels JSON
  const parsedIssues = issues.results.map((issue: any) => ({
    ...issue,
    labels: issue.labels ? JSON.parse(issue.labels) : []
  }));

  return c.json({ issues: parsedIssues });
});

// Web: List sources/projects
app.get('/v1/sources', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sources = await c.env.DB.prepare(`
    SELECT id, name, type, last_issue_number
    FROM sources
    WHERE user_id = ?
    ORDER BY name ASC
  `).bind(user.id).all();

  return c.json({ sources: sources.results });
});

// Web: Get single issue
app.get('/v1/issues/:id', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const issueId = c.req.param('id');

  const issue = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ? AND i.id = ?
  `).bind(user.id, issueId).first();

  if (!issue) {
    return c.json({ error: 'Issue not found' }, 404);
  }

  // Parse labels JSON
  const parsedIssue = {
    ...issue,
    labels: issue.labels ? JSON.parse(issue.labels as string) : []
  };

  return c.json({ issue: parsedIssue });
});

// Web: Get sessions
app.get('/v1/sessions', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sessions = await c.env.DB.prepare(`
    SELECT
      s.*,
      src.name as source_name
    FROM issue_sessions s
    LEFT JOIN sources src ON src.id = s.source_id
    WHERE s.user_id = ?
    ORDER BY s.last_issue_at DESC
    LIMIT 50
  `).bind(user.id).all();

  return c.json({ sessions: sessions.results });
});

// Web: Get issues for session
app.get('/v1/sessions/:id/issues', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sessionId = c.req.param('id');

  const issues = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ? AND i.session_id = ?
    ORDER BY i.created_at ASC
  `).bind(user.id, sessionId).all();

  // Parse labels JSON
  const parsedIssues = issues.results.map((issue: any) => ({
    ...issue,
    labels: issue.labels ? JSON.parse(issue.labels) : []
  }));

  return c.json({ issues: parsedIssues });
});

// Device: Register device
app.post('/v1/devices/register', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { device_id, hardware_uuid, device_name, device_type, platform, platform_version } = await c.req.json();
  const now = Date.now();

  // Check if device exists
  const existing = await c.env.DB.prepare(`
    SELECT * FROM devices WHERE hardware_uuid = ? AND user_id = ?
  `).bind(hardware_uuid, user.id).first();

  if (existing) {
    // Update last_seen and metadata
    await c.env.DB.prepare(`
      UPDATE devices
      SET last_seen = ?, device_name = ?, platform_version = ?
      WHERE id = ?
    `).bind(now, device_name, platform_version, existing.id).run();

    return c.json({ device_id: existing.id });
  }

  // Create new device
  await c.env.DB.prepare(`
    INSERT INTO devices (
      id, user_id, hardware_uuid, device_name, device_type,
      platform, platform_version, first_seen, last_seen
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    device_id,
    user.id,
    hardware_uuid,
    device_name,
    device_type,
    platform,
    platform_version,
    now,
    now
  ).run();

  return c.json({ device_id });
});

// Device Issue Tracking: Record that device saw issue
app.post('/v1/device-tracking/record', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { issue_id, device_id, client } = await c.req.json();
  const now = Date.now();

  // Upsert tracking record
  await c.env.DB.prepare(`
    INSERT INTO device_issue_tracking (issue_id, device_id, client, first_seen, last_seen)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(issue_id, device_id) DO UPDATE SET
      last_seen = excluded.last_seen
  `).bind(issue_id, device_id, client, now, now).run();

  return c.json({ success: true });
});

// Device Issue Tracking: Get tracking for issue
app.get('/v1/device-tracking/:issue_id', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const issueId = c.req.param('issue_id');

  const tracking = await c.env.DB.prepare(`
    SELECT
      dit.*,
      d.device_name,
      d.device_type,
      d.platform
    FROM device_issue_tracking dit
    JOIN devices d ON d.id = dit.device_id
    JOIN issues i ON i.id = dit.issue_id
    WHERE dit.issue_id = ? AND i.user_id = ?
    ORDER BY dit.last_seen DESC
  `).bind(issueId, user.id).all();

  return c.json({ tracking: tracking.results });
});

// Source Sequences: Get next beads_id for source
app.post('/v1/sources/:source_id/next-id', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sourceId = c.req.param('source_id');

  // Verify source belongs to user
  const source = await c.env.DB.prepare(`
    SELECT id FROM sources WHERE id = ? AND user_id = ?
  `).bind(sourceId, user.id).first();

  if (!source) {
    return c.json({ error: 'Source not found' }, 404);
  }

  // Initialize sequence if not exists
  await c.env.DB.prepare(`
    INSERT INTO source_sequences (source_id, next_beads_id)
    VALUES (?, 1)
    ON CONFLICT(source_id) DO NOTHING
  `).bind(sourceId).run();

  // Get and increment next ID atomically
  const result = await c.env.DB.prepare(`
    UPDATE source_sequences
    SET next_beads_id = next_beads_id + 1
    WHERE source_id = ?
    RETURNING next_beads_id - 1 as beads_id_num
  `).bind(sourceId).first<{ beads_id_num: number }>();

  if (!result) {
    return c.json({ error: 'Failed to generate beads_id' }, 500);
  }

  return c.json({
    beads_id: `bd-${result.beads_id_num}`,
    beads_id_num: result.beads_id_num
  });
});

// Source Sequences: Update sequence (when desktop syncs higher IDs)
app.post('/v1/sources/:source_id/update-sequence', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sourceId = c.req.param('source_id');
  const { next_beads_id } = await c.req.json();

  // Verify source belongs to user
  const source = await c.env.DB.prepare(`
    SELECT id FROM sources WHERE id = ? AND user_id = ?
  `).bind(sourceId, user.id).first();

  if (!source) {
    return c.json({ error: 'Source not found' }, 404);
  }

  // Update only if higher
  await c.env.DB.prepare(`
    INSERT INTO source_sequences (source_id, next_beads_id)
    VALUES (?, ?)
    ON CONFLICT(source_id) DO UPDATE SET
      next_beads_id = MAX(next_beads_id, excluded.next_beads_id)
  `).bind(sourceId, next_beads_id).run();

  return c.json({ success: true });
});

// Sync Logs: Get sync history with filters
app.get('/v1/sync-logs', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sourceId = c.req.query('source_id');
  const deviceId = c.req.query('device_id');
  const status = c.req.query('status');
  const operation = c.req.query('operation');
  const limit = parseInt(c.req.query('limit') || '50');
  const offset = parseInt(c.req.query('offset') || '0');

  // Build dynamic query
  let query = 'SELECT * FROM sync_logs WHERE user_id = ?';
  const params: any[] = [user.id];

  if (sourceId) {
    query += ' AND source_id = ?';
    params.push(sourceId);
  }

  if (deviceId) {
    query += ' AND device_id = ?';
    params.push(deviceId);
  }

  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }

  if (operation) {
    query += ' AND operation = ?';
    params.push(operation);
  }

  query += ' ORDER BY started_at DESC LIMIT ? OFFSET ?';
  params.push(limit, offset);

  const logs = await c.env.DB.prepare(query).bind(...params).all();

  // Parse JSON fields
  const parsedLogs = logs.results.map((log: any) => ({
    ...log,
    issue_ids: log.issue_ids ? JSON.parse(log.issue_ids) : [],
    conflict_details: log.conflict_details ? JSON.parse(log.conflict_details) : []
  }));

  return c.json({ logs: parsedLogs, count: parsedLogs.length });
});

// Sync Logs: Get single sync log by ID
app.get('/v1/sync-logs/:id', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const logId = c.req.param('id');

  const log = await c.env.DB.prepare(`
    SELECT * FROM sync_logs WHERE id = ? AND user_id = ?
  `).bind(logId, user.id).first();

  if (!log) {
    return c.json({ error: 'Sync log not found' }, 404);
  }

  // Parse JSON fields
  const parsedLog = {
    ...log,
    issue_ids: log.issue_ids ? JSON.parse(log.issue_ids as string) : [],
    conflict_details: log.conflict_details ? JSON.parse(log.conflict_details as string) : []
  };

  return c.json({ log: parsedLog });
});

// Sync Stats: Get sync statistics
app.get('/v1/sync-stats', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sourceId = c.req.query('source_id');
  const deviceId = c.req.query('device_id');
  const period = c.req.query('period'); // e.g., '7d', '30d'

  // Calculate time window
  let sinceTimestamp = 0;
  if (period) {
    const match = period.match(/^(\d+)([dhm])$/);
    if (match) {
      const value = parseInt(match[1]);
      const unit = match[2];
      const now = Date.now();
      if (unit === 'd') sinceTimestamp = now - (value * 24 * 60 * 60 * 1000);
      if (unit === 'h') sinceTimestamp = now - (value * 60 * 60 * 1000);
      if (unit === 'm') sinceTimestamp = now - (value * 60 * 1000);
    }
  }

  // Build dynamic query
  let whereClause = 'WHERE user_id = ?';
  const params: any[] = [user.id];

  if (sourceId) {
    whereClause += ' AND source_id = ?';
    params.push(sourceId);
  }

  if (deviceId) {
    whereClause += ' AND device_id = ?';
    params.push(deviceId);
  }

  if (sinceTimestamp > 0) {
    whereClause += ' AND started_at >= ?';
    params.push(sinceTimestamp);
  }

  interface SyncStats {
    total_syncs: number;
    successful_syncs: number;
    failed_syncs: number;
    avg_duration_ms: number | null;
    total_issues_synced: number | null;
    total_issues_created: number | null;
    total_issues_updated: number | null;
  }

  // Get overall stats
  const stats = await c.env.DB.prepare(`
    SELECT
      COUNT(*) as total_syncs,
      SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as successful_syncs,
      SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_syncs,
      AVG(duration_ms) as avg_duration_ms,
      SUM(issue_count) as total_issues_synced,
      SUM(issues_created) as total_issues_created,
      SUM(issues_updated) as total_issues_updated
    FROM sync_logs
    ${whereClause}
  `).bind(...params).first<SyncStats>();

  // Get error breakdown
  const errorBreakdown = await c.env.DB.prepare(`
    SELECT error_code, COUNT(*) as count
    FROM sync_logs
    ${whereClause} AND status = 'failed' AND error_code IS NOT NULL
    GROUP BY error_code
    ORDER BY count DESC
  `).bind(...params).all();

  if (!stats) {
    return c.json({ error: 'Failed to get stats' }, 500);
  }

  const successRate = stats.total_syncs > 0
    ? (stats.successful_syncs / stats.total_syncs * 100).toFixed(2)
    : 0;

  return c.json({
    stats: {
      ...stats,
      success_rate_percent: parseFloat(successRate as string)
    },
    error_breakdown: errorBreakdown.results
  });
});

// Get all repositories with issue counts
app.get('/v1/repositories', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  interface RepositoryStats {
    git_repo_url: string;
    total_issues: number;
    open_issues: number;
    closed_issues: number;
    latest_activity: number | null;
  }

  const repos = await c.env.DB.prepare(`
    SELECT
      git_repo_url,
      COUNT(*) as total_issues,
      SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) as open_issues,
      SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END) as closed_issues,
      MAX(updated_at) as latest_activity
    FROM issues
    WHERE user_id = ? AND git_repo_url IS NOT NULL
    GROUP BY git_repo_url
    ORDER BY latest_activity DESC
  `).bind(user.id).all<RepositoryStats>();

  return c.json({
    repositories: repos.results || []
  });
});

// Helper: Authenticate user by session or API key
async function authenticate(c: any): Promise<any | null> {
  const auth = c.get('auth');

  // Try session authentication first (from cookies)
  try {
    const session = await auth.api.getSession({ headers: c.req.raw.headers });
    if (session?.user) {
      return session.user;
    }
  } catch (error) {
    // Session auth failed, try API key
  }

  // Try API key authentication (for CLI/MCP)
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '') || c.req.query('api_key');
  if (apiKey) {
    const user = await c.env.DB.prepare(`
      SELECT * FROM users WHERE api_key = ?
    `).bind(apiKey).first();
    return user;
  }

  return null;
}

export default app;
