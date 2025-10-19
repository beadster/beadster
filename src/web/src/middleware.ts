import { defineMiddleware } from 'astro:middleware';
import { createAuth } from './lib/auth';

const PUBLIC_ROUTES = ['/', '/login', '/api/'];

export const onRequest = defineMiddleware(async (context, next) => {
  const { url, locals } = context;

  const db = locals.runtime?.env?.DB;
  if (!db) {
    return next();
  }

  // Try API key authentication first (for native apps)
  const authHeader = context.request.headers.get('authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const apiKey = authHeader.substring(7);
    console.log('[auth] Received API key:', apiKey.substring(0, 8) + '...');

    try {
      const result = await db.prepare(
        'SELECT id, email, name, github_login FROM users WHERE api_key = ?'
      ).bind(apiKey).first();

      if (result) {
        console.log('[auth] API key authenticated as:', result.github_login);
        locals.user = {
          id: result.id,
          email: result.email,
          name: result.name,
          github_login: result.github_login,
        };
        return next();
      } else {
        console.log('[auth] API key not found in database');
      }
    } catch (err) {
      console.error('[auth] API key validation error:', err);
    }
  }

  // Fall back to Better Auth session (for web)
  try {
    const secret = locals.runtime?.env?.BETTER_AUTH_SECRET;
    const auth = createAuth(db, secret, locals.runtime?.env);

    const session = await auth.api.getSession({
      headers: context.request.headers,
    });

    if (session?.user) {
      locals.user = {
        id: session.user.id,
        email: session.user.email,
        name: session.user.name,
        github_login: session.user.github_login,
      };
    }
  } catch (err) {
    console.error('[auth] Session validation error:', err);
  }

  return next();
});
