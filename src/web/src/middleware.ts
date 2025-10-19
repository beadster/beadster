import { defineMiddleware } from 'astro:middleware';
import { createAuth } from './lib/auth';

export const onRequest = defineMiddleware(async (context, next) => {
  const runtime = context.locals.runtime;

  if (!runtime?.env) {
    console.error('[auth] Runtime environment not available');
    return next();
  }

  const { DB, BETTER_AUTH_SECRET, BASE_URL, GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET } = runtime.env;

  if (!DB || !BETTER_AUTH_SECRET || !GITHUB_CLIENT_ID || !GITHUB_CLIENT_SECRET) {
    console.error('[auth] Missing required environment variables');
    return next();
  }

  const auth = createAuth(
    DB,
    BETTER_AUTH_SECRET,
    BASE_URL || context.url.origin,
    GITHUB_CLIENT_ID,
    GITHUB_CLIENT_SECRET
  );

  // Handle Better Auth routes
  if (context.url.pathname.startsWith('/api/auth/')) {
    return await auth.handler(context.request);
  }

  // For all other routes, check auth session
  try {
    const session = await auth.api.getSession({ headers: context.request.headers });
    context.locals.user = session?.user || null;
    context.locals.session = session || null;
  } catch (error) {
    console.error('[auth] Failed to get session:', error);
    context.locals.user = null;
    context.locals.session = null;
  }

  return next();
});
