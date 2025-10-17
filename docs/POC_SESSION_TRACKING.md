# Session Tracking in PoC

## How It Works

1. MCP server adds session labels when creating issues
2. Sync daemon extracts session metadata from labels
3. Cloud stores session info in database
4. Web UI shows issues grouped by session

## MCP Server Updates

Add session label capture:

```typescript
// In MCP server (beadshub-mcp/src/index.ts)

async function getSessionId(): Promise<string> {
  const sessionFile = '/tmp/beadshub-session-id';

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
  // Detect client from environment or parent process
  if (process.env.CLAUDE_CODE) return 'claude-code';
  if (process.env.CLAUDE_DESKTOP) return 'claude-desktop';
  return 'unknown';
}

// When creating issue
server.setRequestHandler('tools/call', async (request) => {
  const { name, arguments: args } = request.params;

  if (name === 'todo_create') {
    const beadsDir = findBeadsDir();

    // Add session labels
    const sessionId = await getSessionId();
    const client = getClientType();
    const projectName = path.basename(beadsDir);

    const labels = [
      ...(args.labels || []),
      `session:${sessionId}`,
      `client:${client}`,
      `project:${projectName}`
    ];

    let cmd = `cd ${beadsDir} && bd create "${args.title}"`;
    if (args.body) cmd += ` --body="${args.body}"`;
    if (args.priority) cmd += ` --priority=${args.priority}`;

    for (const label of labels) {
      cmd += ` --label="${label}"`;
    }
    cmd += ' --json';

    const output = execSync(cmd, { encoding: 'utf8' });
    const issue = JSON.parse(output);

    return {
      content: [{
        type: 'text',
        text: `✓ Created todo #${issue.id}: ${args.title}\n\nSession: ${sessionId.substring(0, 16)}...\nClient: ${client}`
      }]
    };
  }

  // ... rest of handlers
});
```

## Sync Daemon Updates

Extract session metadata from labels:

```swift
// In CloudAPI.swift

func pushIssues(source: Source, issues: [Issue]) async throws {
    let sourceId = generateSourceId(path: source.path)

    let payload: [String: Any] = [
        "source": [
            "id": sourceId,
            "name": source.name,
            "type": "local",
            "path": source.path
        ],
        "issues": issues.map { issue in
            // Extract session metadata from labels
            let sessionId = extractLabel(from: issue.labels, prefix: "session:")
            let client = extractLabel(from: issue.labels, prefix: "client:")
            let projectName = extractLabel(from: issue.labels, prefix: "project:")

            return [
                "id": "\(sourceId)_\(issue.beadsId)",
                "beads_id": issue.beadsId,
                "title": issue.title,
                "body": issue.body as Any,
                "status": issue.status,
                "priority": issue.priority as Any,
                "labels": issue.labels,
                "created_at": issue.createdAt,
                "updated_at": issue.updatedAt,
                // Add extracted session info
                "session_id": sessionId as Any,
                "client": client as Any,
                "project_name": projectName as Any
            ]
        }
    ]

    // ... rest of push logic
}

private func extractLabel(from labels: [String], prefix: String) -> String? {
    return labels.first { $0.hasPrefix(prefix) }?
        .replacingOccurrences(of: prefix, with: "")
}
```

## Cloud API Updates

Store and query by session:

```typescript
// In src/index.ts

app.post('/api/sync/push', async (c) => {
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '');
  const user = await authenticate(c.env.DB, apiKey);

  const { source, issues } = await c.req.json();

  // Upsert source
  await c.env.DB.prepare(`
    INSERT INTO sources (id, user_id, name, type, path, last_sync)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET last_sync = ?
  `).bind(
    source.id,
    user.id,
    source.name,
    source.type,
    source.path,
    Date.now(),
    Date.now()
  ).run();

  // Upsert issues
  for (const issue of issues) {
    await c.env.DB.prepare(`
      INSERT INTO issues (
        id, user_id, source_id, beads_id, title, body,
        status, priority, labels,
        session_id, client, project_name,
        synced_at, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        body = excluded.body,
        status = excluded.status,
        priority = excluded.priority,
        labels = excluded.labels,
        session_id = excluded.session_id,
        client = excluded.client,
        project_name = excluded.project_name,
        synced_at = excluded.synced_at,
        updated_at = excluded.updated_at
    `).bind(
      issue.id,
      user.id,
      source.id,
      issue.beads_id,
      issue.title,
      issue.body,
      issue.status,
      issue.priority,
      JSON.stringify(issue.labels),
      issue.session_id,
      issue.client,
      issue.project_name,
      Date.now(),
      issue.created_at,
      issue.updated_at
    ).run();

    // Update session tracking
    if (issue.session_id) {
      await c.env.DB.prepare(`
        INSERT INTO sessions (
          id, user_id, source_id, client, project_name,
          first_issue_at, last_issue_at, issue_count
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT(id) DO UPDATE SET
          last_issue_at = ?,
          issue_count = issue_count + 1
      `).bind(
        issue.session_id,
        user.id,
        source.id,
        issue.client,
        issue.project_name,
        issue.created_at,
        issue.created_at,
        issue.created_at
      ).run();
    }
  }

  return c.json({ synced: issues.length });
});

// Get sessions
app.get('/api/sessions', async (c) => {
  const apiKey = c.req.query('api_key');
  const user = await authenticate(c.env.DB, apiKey);

  const sessions = await c.env.DB.prepare(`
    SELECT
      s.*,
      src.name as source_name
    FROM sessions s
    LEFT JOIN sources src ON src.id = s.source_id
    WHERE s.user_id = ?
    ORDER BY s.last_issue_at DESC
    LIMIT 20
  `).bind(user.id).all();

  return c.json(sessions.results);
});

// Get issues for session
app.get('/api/sessions/:id/issues', async (c) => {
  const apiKey = c.req.query('api_key');
  const user = await authenticate(c.env.DB, apiKey);
  const sessionId = c.req.param('id');

  const issues = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name
    FROM issues i
    JOIN sources s ON s.id = i.source_id
    WHERE i.user_id = ? AND i.session_id = ?
    ORDER BY i.created_at ASC
  `).bind(user.id, sessionId).all();

  return c.json(issues.results);
});
```

## Web UI Updates

Show sessions and group issues:

```astro
---
// src/pages/index.astro
const apiKey = Astro.url.searchParams.get('api_key');
const view = Astro.url.searchParams.get('view') || 'all'; // 'all' or 'sessions'
const sessionId = Astro.url.searchParams.get('session');

let issues = [];
let sessions = [];
let currentSession = null;

if (apiKey) {
  if (view === 'sessions') {
    // Get sessions
    const sessionsResponse = await fetch(
      `https://api.beadshub.com/api/sessions?api_key=${apiKey}`
    );
    sessions = await sessionsResponse.json();
  } else if (sessionId) {
    // Get issues for specific session
    const issuesResponse = await fetch(
      `https://api.beadshub.com/api/sessions/${sessionId}/issues?api_key=${apiKey}`
    );
    issues = await issuesResponse.json();

    // Get session info
    const sessionResponse = await fetch(
      `https://api.beadshub.com/api/sessions?api_key=${apiKey}`
    );
    const allSessions = await sessionResponse.json();
    currentSession = allSessions.find(s => s.id === sessionId);
  } else {
    // Get all issues
    const response = await fetch(
      `https://api.beadshub.com/api/issues?api_key=${apiKey}`
    );
    issues = await response.json();
  }
}

function formatDate(timestamp) {
  return new Date(timestamp).toLocaleString();
}

function formatSessionId(id) {
  return id.substring(0, 20) + '...';
}
---

<html>
<head>
  <title>BeadsHub</title>
  <style>
    body {
      font-family: system-ui;
      max-width: 900px;
      margin: 40px auto;
      padding: 0 20px;
    }
    .nav {
      margin-bottom: 20px;
      border-bottom: 2px solid #ddd;
    }
    .nav a {
      display: inline-block;
      padding: 10px 20px;
      text-decoration: none;
      color: #333;
      border-bottom: 2px solid transparent;
      margin-bottom: -2px;
    }
    .nav a.active {
      border-bottom-color: #0066cc;
      color: #0066cc;
      font-weight: bold;
    }
    .session {
      border: 1px solid #ddd;
      padding: 15px;
      margin: 10px 0;
      border-radius: 8px;
      cursor: pointer;
    }
    .session:hover {
      background: #f5f5f5;
    }
    .session-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .session-title {
      font-weight: bold;
      font-size: 16px;
    }
    .session-meta {
      color: #666;
      font-size: 12px;
      margin-top: 5px;
    }
    .issue {
      border: 1px solid #ddd;
      padding: 15px;
      margin: 10px 0;
      border-radius: 8px;
    }
    .issue-title {
      font-weight: bold;
      font-size: 16px;
    }
    .issue-meta {
      color: #666;
      font-size: 12px;
      margin-top: 5px;
    }
    .status-open { color: green; }
    .status-closed { color: gray; }
    .badge {
      display: inline-block;
      padding: 3px 8px;
      border-radius: 12px;
      font-size: 11px;
      background: #e0e0e0;
      margin-right: 5px;
    }
    .badge.client-claude-code { background: #d4e5ff; }
    .badge.client-claude-desktop { background: #ffe5d4; }
    input { padding: 8px; width: 300px; }
    button { padding: 8px 16px; }
  </style>
</head>
<body>
  <h1>BeadsHub</h1>

  {!apiKey ? (
    <form>
      <input type="text" name="api_key" placeholder="Enter your API key" />
      <button>View Issues</button>
    </form>
  ) : (
    <>
      <div class="nav">
        <a href={`?api_key=${apiKey}&view=all`} class={view === 'all' ? 'active' : ''}>
          All Issues
        </a>
        <a href={`?api_key=${apiKey}&view=sessions`} class={view === 'sessions' ? 'active' : ''}>
          Sessions
        </a>
      </div>

      {view === 'sessions' ? (
        <>
          <h2>Recent Sessions ({sessions.length})</h2>
          {sessions.map(session => (
            <a href={`?api_key=${apiKey}&session=${session.id}`} style="text-decoration: none; color: inherit;">
              <div class="session">
                <div class="session-header">
                  <div class="session-title">
                    {session.project_name || 'Unnamed Session'}
                  </div>
                  <div>
                    <span class={`badge client-${session.client}`}>
                      {session.client}
                    </span>
                    <span class="badge">
                      {session.issue_count} {session.issue_count === 1 ? 'issue' : 'issues'}
                    </span>
                  </div>
                </div>
                <div class="session-meta">
                  Session: {formatSessionId(session.id)}
                  {' • '}
                  Source: {session.source_name || 'Unknown'}
                  {' • '}
                  Last active: {formatDate(session.last_issue_at)}
                </div>
              </div>
            </a>
          ))}
        </>
      ) : currentSession ? (
        <>
          <p>
            <a href={`?api_key=${apiKey}&view=sessions`}>← Back to sessions</a>
          </p>
          <h2>
            {currentSession.project_name || 'Unnamed Session'}
          </h2>
          <div class="session-meta">
            <span class={`badge client-${currentSession.client}`}>
              {currentSession.client}
            </span>
            Session: {formatSessionId(currentSession.id)}
            {' • '}
            {currentSession.issue_count} {currentSession.issue_count === 1 ? 'issue' : 'issues'}
            {' • '}
            {formatDate(currentSession.first_issue_at)} to {formatDate(currentSession.last_issue_at)}
          </div>

          <h3>Issues in this session</h3>
          {issues.map(issue => (
            <div class="issue">
              <div class="issue-title">{issue.title}</div>
              <div class="issue-meta">
                <span class={`status-${issue.status}`}>{issue.status}</span>
                {' • '}
                {issue.source_name}
                {issue.priority && ` • ${issue.priority} priority`}
                {' • '}
                {formatDate(issue.created_at)}
              </div>
              {issue.body && <p>{issue.body}</p>}
            </div>
          ))}
        </>
      ) : (
        <>
          <p>Viewing {issues.length} issues</p>

          {issues.map(issue => (
            <div class="issue">
              <div class="issue-title">{issue.title}</div>
              <div class="issue-meta">
                <span class={`status-${issue.status}`}>{issue.status}</span>
                {' • '}
                {issue.source_name}
                {issue.priority && ` • ${issue.priority} priority`}
                {issue.client && (
                  <>
                    {' • '}
                    <span class={`badge client-${issue.client}`}>
                      {issue.client}
                    </span>
                  </>
                )}
                {issue.session_id && (
                  <>
                    {' • '}
                    <a href={`?api_key=${apiKey}&session=${issue.session_id}`}>
                      View session
                    </a>
                  </>
                )}
              </div>
              {issue.body && <p>{issue.body}</p>}
            </div>
          ))}
        </>
      )}
    </>
  )}
</body>
</html>
```

## Result

**Web UI now shows:**

1. **All Issues view** - See all issues with session badges
2. **Sessions view** - List of recent sessions with counts
3. **Session detail** - All issues from one conversation
4. **Client badges** - Visual indicator of which Claude created it
5. **Session links** - Jump to session from any issue

**Example session view:**

```
Recent Sessions (5)

┌────────────────────────────────────────┐
│ main-app                      [claude-code] [12 issues]
│ Session: session_1234567...
│ Source: main-app • Last active: Oct 17, 3:45 PM
└────────────────────────────────────────┘

┌────────────────────────────────────────┐
│ Planning work                 [claude-desktop] [3 issues]
│ Session: session_9876543...
│ Source: inbox • Last active: Oct 17, 2:10 PM
└────────────────────────────────────────┘
```

This gives you full visibility into which Claude conversation created which todos!
