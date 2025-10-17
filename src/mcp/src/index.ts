#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import os from 'os';

const server = new Server(
  {
    name: 'beadster-mcp',
    version: '0.1.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler('tools/list', async () => ({
  tools: [
    {
      name: 'todo_create',
      description: 'Create a todo using Beads with session tracking',
      inputSchema: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'Todo title' },
          description: { type: 'string', description: 'Todo description' },
          priority: { type: 'number', enum: [0, 1, 2, 3, 4], description: 'Priority (0=highest, 4=lowest)' },
          labels: { type: 'array', items: { type: 'string' }, description: 'Labels' },
          type: { type: 'string', enum: ['bug', 'feature', 'task', 'epic', 'chore'], description: 'Issue type' }
        },
        required: ['title']
      }
    },
    {
      name: 'todo_list',
      description: 'List todos',
      inputSchema: {
        type: 'object',
        properties: {
          status: { type: 'string', enum: ['open', 'closed', 'all'], description: 'Filter by status' },
          labels: { type: 'array', items: { type: 'string' }, description: 'Filter by labels' }
        }
      }
    },
    {
      name: 'todo_complete',
      description: 'Mark todo as complete',
      inputSchema: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'Issue ID (e.g., beadster-1)' }
        },
        required: ['id']
      }
    },
    {
      name: 'todo_ready',
      description: 'List todos ready to work on (no blockers)',
      inputSchema: {
        type: 'object',
        properties: {}
      }
    }
  ]
}));

server.setRequestHandler('tools/call', async (request) => {
  const { name, arguments: args } = request.params as { name: string; arguments: any };

  const beadsDir = findBeadsDir();

  switch (name) {
    case 'todo_create': {
      // Generate session labels
      const sessionLabels = await getSessionLabels(beadsDir);
      const allLabels = [...(args.labels || []), ...sessionLabels];

      let cmd = `cd "${beadsDir}" && bd create "${args.title.replace(/"/g, '\\"')}"`;
      if (args.description) cmd += ` -d "${args.description.replace(/"/g, '\\"')}"`;
      if (args.priority !== undefined) cmd += ` -p ${args.priority}`;
      if (args.type) cmd += ` -t ${args.type}`;
      if (allLabels.length > 0) {
        cmd += ` -l "${allLabels.join(',')}"`;
      }
      cmd += ' --json';

      const output = execSync(cmd, { encoding: 'utf8' });
      const issue = JSON.parse(output);

      const sessionId = sessionLabels.find(l => l.startsWith('session:'))?.split(':')[1];
      const client = sessionLabels.find(l => l.startsWith('client:'))?.split(':')[1];

      return {
        content: [{
          type: 'text',
          text: `✓ Created todo: ${issue.id}\n\nTitle: ${args.title}\nSession: ${sessionId?.substring(0, 20)}...\nClient: ${client}`
        }]
      };
    }

    case 'todo_list': {
      let cmd = `cd "${beadsDir}" && bd list --json`;

      const output = execSync(cmd, { encoding: 'utf8' });
      const issues = JSON.parse(output);

      // Filter if needed
      let filtered = issues;
      if (args.status && args.status !== 'all') {
        filtered = filtered.filter((i: any) => i.status === args.status);
      }
      if (args.labels && args.labels.length > 0) {
        filtered = filtered.filter((i: any) =>
          args.labels.some((l: string) => i.labels?.includes(l))
        );
      }

      let text = `Found ${filtered.length} todo(s):\n\n`;
      for (const issue of filtered) {
        text += `${issue.id}: ${issue.title}`;
        if (issue.priority !== undefined) text += ` [P${issue.priority}]`;
        text += ` [${issue.status}]`;
        if (issue.labels?.length) text += ` (${issue.labels.join(', ')})`;
        text += '\n';
      }

      return {
        content: [{ type: 'text', text }]
      };
    }

    case 'todo_complete': {
      const cmd = `cd "${beadsDir}" && bd close ${args.id}`;
      execSync(cmd);

      return {
        content: [{
          type: 'text',
          text: `✓ Marked ${args.id} as complete`
        }]
      };
    }

    case 'todo_ready': {
      const cmd = `cd "${beadsDir}" && bd ready --json`;
      const output = execSync(cmd, { encoding: 'utf8' });
      const ready = JSON.parse(output);

      if (ready.length === 0) {
        return {
          content: [{
            type: 'text',
            text: 'No ready work! Everything is blocked or complete.'
          }]
        };
      }

      let text = `Ready to work on (${ready.length}):\n\n`;
      for (const issue of ready) {
        text += `${issue.id}: ${issue.title}`;
        if (issue.priority !== undefined) text += ` [P${issue.priority}]`;
        text += '\n';
      }

      return {
        content: [{ type: 'text', text }]
      };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

function findBeadsDir(): string {
  let dir = process.cwd();

  // Search up for .beads/
  while (dir !== '/' && dir.length > 1) {
    if (fs.existsSync(path.join(dir, '.beads'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }

  // Use inbox as fallback
  const inbox = path.join(os.homedir(), '.beadster', 'inbox');
  if (!fs.existsSync(path.join(inbox, '.beads'))) {
    fs.mkdirSync(inbox, { recursive: true });
    execSync(`cd "${inbox}" && bd init`);
  }

  return inbox;
}

async function getSessionLabels(beadsDir: string): Promise<string[]> {
  const sessionId = await getSessionId();
  const client = getClientType();
  const projectName = path.basename(beadsDir);

  return [
    `session:${sessionId}`,
    `client:${client}`,
    `project:${projectName}`
  ];
}

async function getSessionId(): Promise<string> {
  const sessionFile = '/tmp/beadster-session-id';

  if (fs.existsSync(sessionFile)) {
    const data = JSON.parse(fs.readFileSync(sessionFile, 'utf8'));
    // Active if < 24 hours old
    if (Date.now() - data.created_at < 24 * 60 * 60 * 1000) {
      return data.session_id;
    }
  }

  // Create new session
  const sessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 8)}`;
  fs.writeFileSync(sessionFile, JSON.stringify({
    session_id: sessionId,
    created_at: Date.now()
  }));

  return sessionId;
}

function getClientType(): string {
  // Detect client from environment
  if (process.env.CLAUDE_CODE) return 'claude-code';
  if (process.env.CLAUDE_DESKTOP) return 'claude-desktop';

  // Try to detect from parent process
  try {
    const ppid = process.ppid;
    const processName = execSync(`ps -p ${ppid} -o comm=`, { encoding: 'utf8' }).trim();
    if (processName.includes('Claude')) return 'claude-desktop';
    if (processName.includes('code')) return 'claude-code';
  } catch (e) {
    // Ignore
  }

  return 'unknown';
}

const transport = new StdioServerTransport();
server.connect(transport);
