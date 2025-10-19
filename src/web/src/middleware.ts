import { defineMiddleware } from 'astro:middleware';
import { createAuth } from './lib/auth';

const PUBLIC_ROUTES = ['/', '/login', '/api/'];

export const onRequest = defineMiddleware(async (context, next) => {
  const { url, locals } = context;

  // Get session from Better Auth
  const db = locals.runtime?.env?.DB;
  if (db) {
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
      console.error('[auth]', err);
    }
  }

  return next();
});
