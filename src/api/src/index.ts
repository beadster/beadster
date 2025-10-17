import { Hono } from 'hono';
import { cors } from 'hono/cors';

type Bindings = {
  DB: D1Database;
  ENVIRONMENT: string;
};

const app = new Hono<{ Bindings: Bindings }>();

// CORS
app.use('/*', cors());

// Health check
app.get('/', (c) => {
  return c.json({
    name: 'beadster-api',
    version: '0.1.0',
    status: 'ok'
  });
});

// Auth: Register/Get API key (for PoC)
app.post('/api/auth/register', async (c) => {
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
app.post('/api/sync/push', async (c) => {
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '');
  const user = await authenticate(c.env.DB, apiKey);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const { source, issues } = await c.req.json();
  const now = Date.now();

  // Upsert source
  await c.env.DB.prepare(`
    INSERT INTO sources (id, user_id, name, type, path, last_sync, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      last_sync = excluded.last_sync,
      updated_at = excluded.updated_at
  `).bind(
    source.id,
    user.id,
    source.name,
    source.type || 'local',
    source.path,
    now,
    now,
    now
  ).run();

  // Upsert issues
  for (const issue of issues) {
    await c.env.DB.prepare(`
      INSERT INTO issues (
        id, user_id, source_id, beads_id, title, body,
        status, priority, labels,
        session_id, client, project_name,
        synced_at, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        body = excluded.body,
        status = excluded.status,
        priority = excluded.priority,
        labels = excluded.labels,
        session_id = excluded.session_id,
        client = excluded.client,
        project_name = excluded.project_name,
        synced_at = excluded.synced_at,
        updated_at = excluded.updated_at
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
      now,
      issue.created_at,
      issue.updated_at
    ).run();

    // Update session tracking
    if (issue.session_id) {
      await c.env.DB.prepare(`
        INSERT INTO sessions (
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

  return c.json({ synced: issues.length });
});

// Sync: Pull changes from cloud
app.get('/api/sync/pull', async (c) => {
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '');
  const user = await authenticate(c.env.DB, apiKey);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sourceId = c.req.query('source_id');
  const since = parseInt(c.req.query('since') || '0');

  if (!sourceId) {
    return c.json({ error: 'source_id required' }, 400);
  }

  const changes = await c.env.DB.prepare(`
    SELECT * FROM issues
    WHERE source_id = ? AND user_id = ? AND updated_at > ?
    ORDER BY updated_at ASC
  `).bind(sourceId, user.id, since).all();

  return c.json(changes.results);
});

// Web: List all issues
app.get('/api/issues', async (c) => {
  const apiKey = c.req.query('api_key');
  const user = await authenticate(c.env.DB, apiKey);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const issues = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ?
    ORDER BY i.created_at DESC
  `).bind(user.id).all();

  return c.json(issues.results);
});

// Web: Get sessions
app.get('/api/sessions', async (c) => {
  const apiKey = c.req.query('api_key');
  const user = await authenticate(c.env.DB, apiKey);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const sessions = await c.env.DB.prepare(`
    SELECT
      s.*,
      src.name as source_name
    FROM sessions s
    LEFT JOIN sources src ON src.id = s.source_id
    WHERE s.user_id = ?
    ORDER BY s.last_issue_at DESC
    LIMIT 50
  `).bind(user.id).all();

  return c.json(sessions.results);
});

// Web: Get issues for session
app.get('/api/sessions/:id/issues', async (c) => {
  const apiKey = c.req.query('api_key');
  const user = await authenticate(c.env.DB, apiKey);

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

  return c.json(issues.results);
});

// Helper: Authenticate user by API key
async function authenticate(db: D1Database, apiKey: string | undefined) {
  if (!apiKey) {
    return null;
  }

  const user = await db.prepare(`
    SELECT * FROM users WHERE api_key = ?
  `).bind(apiKey).first();

  return user;
}

export default app;
