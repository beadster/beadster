import type { APIRoute } from 'astro';

/**
 * Exchange GitHub OAuth code for API key (for native apps)
 * This is used by desktop/mobile apps that have their own OAuth client
 */
export const POST: APIRoute = async ({ request, locals }) => {
  try {
    const { code, client_id } = await request.json();

    if (!code || !client_id) {
      return new Response(JSON.stringify({ error: 'Missing code or client_id' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const db = locals.runtime?.env?.DB;
    if (!db) {
      return new Response(JSON.stringify({ error: 'Database not available' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Exchange code for access token with GitHub
    const clientSecret = locals.runtime?.env?.GITHUB_DESKTOP_CLIENT_SECRET;
    console.log('[native-exchange] client_id:', client_id);
    console.log('[native-exchange] has client_secret:', !!clientSecret);

    const tokenResponse = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        client_id,
        client_secret: clientSecret,
        code
      })
    });

    if (!tokenResponse.ok) {
      const errorBody = await tokenResponse.text();
      console.error('[native-exchange] GitHub token exchange failed:', tokenResponse.status, errorBody);
      return new Response(JSON.stringify({ error: 'Failed to exchange code', details: errorBody }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const { access_token } = await tokenResponse.json();

    // Get user info from GitHub
    console.log('[native-exchange] Fetching user info with access_token');
    const userResponse = await fetch('https://api.github.com/user', {
      headers: {
        'Authorization': `Bearer ${access_token}`,
        'Accept': 'application/json',
        'User-Agent': 'Beadster'
      }
    });

    if (!userResponse.ok) {
      const errorBody = await userResponse.text();
      console.error('[native-exchange] Failed to get user info:', userResponse.status, errorBody);
      return new Response(JSON.stringify({ error: 'Failed to get user info', details: errorBody }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const githubUser = await userResponse.json();

    // Check if user exists
    let user = await db.prepare(
      'SELECT id, api_key FROM users WHERE github_id = ?'
    ).bind(githubUser.id).first();

    const now = Math.floor(Date.now() / 1000);

    if (!user) {
      // Create new user
      const { generateId } = await import('@systemoperator/common/id');

      const userId = generateId();
      const apiKey = generateId();

      await db.prepare(`
        INSERT INTO users (
          id, github_id, github_login, github_name, github_email,
          github_avatar_url, email, name, image, api_key,
          created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(
        userId,
        githubUser.id,
        githubUser.login,
        githubUser.name,
        githubUser.email,
        githubUser.avatar_url,
        githubUser.email,
        githubUser.name,
        githubUser.avatar_url,
        apiKey,
        now,
        now
      ).run();

      user = { id: userId, api_key: apiKey };
    }

    // Return API key and user info
    return new Response(JSON.stringify({
      api_key: user.api_key,
      user: {
        id: user.id,
        github_login: githubUser.login,
        github_name: githubUser.name,
        github_email: githubUser.email
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Native auth exchange error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
