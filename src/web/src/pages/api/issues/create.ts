import type { APIRoute } from 'astro';
import { createIssue } from '../../../../../shared/database';

export const POST: APIRoute = async ({ request, locals }) => {
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

  try {
    const data = await request.json();
    const { title, body, priority, status, source_id, issue_type, assignee } = data;

    if (!title) {
      return new Response(JSON.stringify({ error: 'Title required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!source_id) {
      return new Response(JSON.stringify({ error: 'Source required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const result = await createIssue(db, user.id, {
      source_id,
      title,
      body,
      status,
      priority,
      issue_type,
      assignee: assignee || null
    });

    return new Response(JSON.stringify(result), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('Create issue error:', error);
    const errorMessage = error instanceof Error ? error.message : 'Failed to create issue';
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
