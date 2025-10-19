import type { APIRoute } from 'astro';
import { closeIssue } from '../../../../../../shared/database';

export const POST: APIRoute = async ({ params, locals }) => {
  const db = locals.runtime?.env?.DB;
  const user = locals.user;

  if (!db) {
    return new Response(JSON.stringify({ error: 'Database not available' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  if (!user) {
    return new Response(JSON.stringify({ error: 'Not authenticated' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  const { id } = params;
  if (!id) {
    return new Response(JSON.stringify({ error: 'Issue ID required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    await closeIssue(db, user.id, id);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Close issue error:', error);
    return new Response(JSON.stringify({ error: 'Failed to close issue' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
