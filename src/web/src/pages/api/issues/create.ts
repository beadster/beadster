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
    const { title, body, priority, status, source_id } = data;

    if (!title) {
      return new Response(JSON.stringify({ error: 'Title required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!source_id) {
      return new Response(JSON.stringify({ error: 'Source required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Generate IDs
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);

    // Get user (first available for demo)
    const user = await db.prepare('SELECT id FROM users LIMIT 1').first();
    if (!user) {
      return new Response(JSON.stringify({
        error: 'No user found. Sync daemon needs to run first.'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get source and increment issue number
    const source: any = await db.prepare(`
      SELECT id, name, last_issue_number FROM sources WHERE id = ? AND user_id = ?
    `).bind(source_id, user.id).first();

    if (!source) {
      return new Response(JSON.stringify({ error: 'Source not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
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
