import type { APIRoute } from 'astro';

export const prerender = false;

export const GET: APIRoute = async ({ redirect, locals }) => {
  const db = locals.runtime.env.DB;
  const secret = locals.runtime.env.BETTER_AUTH_SECRET;

  // Call better-auth sign-out
  const auth = (await import('../../../lib/auth')).createAuth(db, secret, locals.runtime.env);
  await auth.api.signOut({ headers: {} } as any);

  // Redirect to home
  return redirect('/', 302);
};

export const POST: APIRoute = async ({ redirect, locals }) => {
  const db = locals.runtime.env.DB;
  const secret = locals.runtime.env.BETTER_AUTH_SECRET;

  // Call better-auth sign-out
  const auth = (await import('../../../lib/auth')).createAuth(db, secret, locals.runtime.env);
  await auth.api.signOut({ headers: {} } as any);

  // Redirect to home
  return redirect('/', 302);
};
