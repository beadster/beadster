import type { APIContext } from 'astro';

/**
 * DELETE /api/tokens/:id - Revoke a token
 */
export async function DELETE({ params, locals }: APIContext) {
  const user = locals.user;
  if (!user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
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

  const { id } = params;

  try {
    // Verify token belongs to user
    const token = await db.prepare(`
      SELECT id FROM api_tokens
      WHERE id = ? AND user_id = ?
    `).bind(id, user.id).first();

    if (!token) {
      return new Response(JSON.stringify({ error: 'token not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Delete token
    await db.prepare(`
      DELETE FROM api_tokens WHERE id = ?
    `).bind(id).run();

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (err) {
    console.error('failed to delete token:', err);
    return new Response(JSON.stringify({ error: 'failed to delete token' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * GET /api/tokens/:id/usage - Get usage logs for a token
 */
export async function GET({ params, locals }: APIContext) {
  const user = locals.user;
  if (!user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), {
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

  const { id } = params;

  try {
    // Verify token belongs to user
    const token = await db.prepare(`
      SELECT id FROM api_tokens
      WHERE id = ? AND user_id = ?
    `).bind(id, user.id).first();

    if (!token) {
      return new Response(JSON.stringify({ error: 'token not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get usage logs (last 100)
    const result = await db.prepare(`
      SELECT endpoint, method, status, ip_address, user_agent, created_at
      FROM api_token_usage
      WHERE token_id = ?
      ORDER BY created_at DESC
      LIMIT 100
    `).bind(id).all();

    return new Response(JSON.stringify({ usage: result.results }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (err) {
    console.error('failed to get token usage:', err);
    return new Response(JSON.stringify({ error: 'failed to get token usage' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
