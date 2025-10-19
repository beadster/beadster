import type { APIRoute } from 'astro';
import { updateIssue } from '../../../../../../shared/database';

export const POST: APIRoute = async ({ params, request, locals }) => {
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
    const data = await request.json();
    const { title, body, priority, status } = data;

    await updateIssue(db, user.id, id, {
      title,
      body,
      priority,
      status
    });

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Update issue error:', error);
    return new Response(JSON.stringify({ error: 'Failed to update issue' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
