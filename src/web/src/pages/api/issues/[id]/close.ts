import type { APIRoute } from 'astro';

export const POST: APIRoute = async ({ params, locals }) => {
  const db = locals.runtime?.env?.DB;
  if (!db) {
    return new Response(JSON.stringify({ error: 'Database not available' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const { id } = params;
  if (!id) {
    return new Response(JSON.stringify({ error: 'Issue ID required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const now = Math.floor(Date.now() / 1000);

    await db.prepare(`
      UPDATE issues
      SET status = ?, closed_at = ?, updated_at = ?
      WHERE id = ?
    `).bind('closed', now, now, id).run();

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Close issue error:', error);
    return new Response(JSON.stringify({ error: 'Failed to close issue' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
