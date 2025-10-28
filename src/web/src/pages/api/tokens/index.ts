import type { APIContext } from 'astro';

/**
 * GET /api/tokens - List all tokens for the current user
 */
export async function GET({ locals }: APIContext) {
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

  try {
    const result = await db.prepare(`
      SELECT id, name, scopes, last_used, created_at, expires_at
      FROM api_tokens
      WHERE user_id = ?
      ORDER BY created_at DESC
    `).bind(user.id).all();

    const tokens = result.results.map((token: any) => ({
      ...token,
      scopes: JSON.parse(token.scopes)
    }));

    return new Response(JSON.stringify({ tokens }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (err) {
    console.error('failed to list tokens:', err);
    return new Response(JSON.stringify({ error: 'failed to list tokens' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * POST /api/tokens - Create a new API token
 */
export async function POST({ request, locals }: APIContext) {
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

  try {
    const body = await request.json();
    const { name, scopes = ['sync'], expires_in_days } = body;

    if (!name) {
      return new Response(JSON.stringify({ error: 'name is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate scopes
    const validScopes = ['sync', 'read', 'admin'];
    const invalidScopes = scopes.filter((s: string) => !validScopes.includes(s));
    if (invalidScopes.length > 0) {
      return new Response(JSON.stringify({
        error: `invalid scopes: ${invalidScopes.join(', ')}`
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Generate token
    const tokenId = `tok_${generateId()}`;
    const token = `bst_${generateToken(32)}`;
    const createdAt = Date.now();
    const expiresAt = expires_in_days
      ? createdAt + (expires_in_days * 24 * 60 * 60 * 1000)
      : null;

    // Insert token
    await db.prepare(`
      INSERT INTO api_tokens (id, user_id, name, token, scopes, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).bind(
      tokenId,
      user.id,
      name,
      token,
      JSON.stringify(scopes),
      createdAt,
      expiresAt
    ).run();

    return new Response(JSON.stringify({
      id: tokenId,
      name,
      token,
      scopes,
      created_at: createdAt,
      expires_at: expiresAt
    }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (err) {
    console.error('failed to create token:', err);
    return new Response(JSON.stringify({ error: 'failed to create token' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

function generateId(): string {
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}

function generateToken(length: number): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}
