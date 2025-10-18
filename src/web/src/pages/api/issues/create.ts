import type { APIRoute } from 'astro';

export const POST: APIRoute = async ({ request, locals }) => {
  const db = locals.runtime?.env?.DB;
  if (!db) {
    return new Response(JSON.stringify({ error: 'Database not available' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const data = await request.json();
    const { title, body, priority, status } = data;

    if (!title) {
      return new Response(JSON.stringify({ error: 'Title required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Generate IDs
    const id = crypto.randomUUID();
    const beadsId = `web-${Date.now()}`;
    const now = Math.floor(Date.now() / 1000);

    // Get first available user and source (for demo)
    const user = await db.prepare('SELECT id FROM users LIMIT 1').first();
    const source = await db.prepare('SELECT id FROM sources LIMIT 1').first();

    if (!user || !source) {
      return new Response(JSON.stringify({
        error: 'No user or source found. Sync daemon needs to run first to create user and source.'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const result = await db.prepare(`
      INSERT INTO issues (
        id, user_id, source_id, beads_id, title, body,
        status, priority, labels,
        synced_at, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      id,
      user.id,
      source.id,
      beadsId,
      title,
      body || null,
      status || 'open',
      priority !== undefined ? priority : 1,
      '[]',
      now,
      now,
      now
    ).run();

    if (!result.success) {
      throw new Error('Database insert failed');
    }

    return new Response(JSON.stringify({ id, beads_id: beadsId }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Create issue error:', error);
    const errorMessage = error instanceof Error ? error.message : 'Failed to create issue';
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
