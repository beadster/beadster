import type { APIRoute } from 'astro';

/**
 * Get user's API key for native app authentication
 * Requires valid Better Auth session
 */
export const GET: APIRoute = async ({ locals }) => {
  const user = locals.user;

  if (!user) {
    return new Response(JSON.stringify({ error: 'Not authenticated' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const db = locals.runtime?.env?.DB;
    if (!db) {
      return new Response(JSON.stringify({ error: 'Database not available' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get user's api_key
    const result = await db.prepare(
      'SELECT api_key, github_login, github_name, github_email FROM users WHERE id = ?'
    ).bind(user.id).first();

    if (!result || !result.api_key) {
      return new Response(JSON.stringify({ error: 'API key not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({
      api_key: result.api_key,
      user: {
        id: user.id,
        github_login: result.github_login,
        github_name: result.github_name,
        github_email: result.github_email
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Get API key error:', error);
    return new Response(JSON.stringify({ error: 'Failed to get API key' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
