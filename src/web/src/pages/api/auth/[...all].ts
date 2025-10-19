import { createAuth } from '../../../lib/auth';
import type { APIRoute } from 'astro';

export const prerender = false;

const handler: APIRoute = async ({ request, locals }) => {
  const db = locals.runtime.env.DB;
  const secret = locals.runtime.env.BETTER_AUTH_SECRET;
  const auth = createAuth(db, secret, locals.runtime.env);

  return auth.handler(request);
};

export const GET = handler;
export const POST = handler;
export const HEAD = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
