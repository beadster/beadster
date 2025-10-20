import type { APIRoute } from 'astro';
import { createAuth } from '../../../lib/auth';

const handleSignout = async ({ locals, request }: any) => {
  const db = locals.runtime.env.DB;
  const secret = locals.runtime.env.BETTER_AUTH_SECRET;
  const auth = createAuth(db, secret, locals.runtime.env);

  // Create a signout request
  const signOutRequest = new Request(new URL('/api/auth/sign-out', request.url), {
    method: 'POST',
    headers: request.headers,
  });

  // Call better-auth handler for signout
  await auth.handler(signOutRequest);

  // Redirect to home page
  return new Response(null, {
    status: 302,
    headers: {
      Location: '/',
    },
  });
};

export const GET: APIRoute = handleSignout;
export const POST: APIRoute = handleSignout;
