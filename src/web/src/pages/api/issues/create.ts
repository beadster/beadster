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

    // For demo, use hardcoded user (in production, get from auth)
    const userId = 'user-1';
    const sourceId = 'beadster';

    await db.prepare(`
      INSERT INTO issues (
        id, user_id, source_id, beads_id, title, body,
        status, priority, labels,
        synced_at, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      id,
      userId,
      sourceId,
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

    return new Response(JSON.stringify({ id, beads_id: beadsId }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Create issue error:', error);
    return new Response(JSON.stringify({ error: 'Failed to create issue' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
