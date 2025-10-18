# context capture from claude sessions

automatically capture rich context when issues are created during claude sessions

## overview

when you create an issue during a claude code session, beadster can:
- capture conversation context around issue creation
- extract relevant code snippets
- identify related files
- generate detailed summary
- preserve decision rationale
- track implementation notes

## how it works

### basic flow

```
1. user creates issue in claude code session
   ↓
2. sync daemon detects new issue with session_id
   ↓
3. if context_capture enabled for source:
   - find claude session logs
   - extract conversation around issue creation
   - identify mentioned files/code
   - use ai to summarize context
   ↓
4. enrich issue with captured context
   ↓
5. sync enriched issue to cloud
```

### enabling context capture

per-source setting:

```sql
ALTER TABLE sources ADD COLUMN context_capture BOOLEAN DEFAULT 0;
ALTER TABLE sources ADD COLUMN context_window INTEGER DEFAULT 10;  -- messages before/after
```

enable for specific source:

```typescript
PATCH /api/sources/:id
{
  "context_capture": true,
  "context_window": 20  // capture 20 messages before/after
}
```

## claude session logs

### finding session logs

claude code stores conversation in:
- macOS: `~/Library/Application Support/Claude/`
- linux: `~/.config/Claude/`
- windows: `%APPDATA%/Claude/`

session format:
```json
{
  "session_id": "sess_abc123",
  "messages": [
    {
      "role": "user",
      "content": "can you add rate limiting to the api?",
      "timestamp": 1234567890
    },
    {
      "role": "assistant",
      "content": "I'll add rate limiting. Let me create an issue to track this...",
      "timestamp": 1234567891,
      "tool_calls": [
        {
          "tool": "mcp_todo_create",
          "input": {
            "title": "add rate limiting to api",
            "body": "prevent abuse by limiting requests per user"
          }
        }
      ]
    }
  ]
}
```

### extracting context window

```typescript
async function extractContextWindow(sessionId: string, issueCreatedAt: number) {
  const sessionLog = await readSessionLog(sessionId);

  // find message where issue was created
  const creationIndex = sessionLog.messages.findIndex(m =>
    m.timestamp === issueCreatedAt &&
    m.tool_calls?.some(t => t.tool === 'mcp_todo_create')
  );

  if (creationIndex === -1) return null;

  const windowSize = 10;  // configurable
  const start = Math.max(0, creationIndex - windowSize);
  const end = Math.min(sessionLog.messages.length, creationIndex + windowSize);

  return {
    before: sessionLog.messages.slice(start, creationIndex),
    creation: sessionLog.messages[creationIndex],
    after: sessionLog.messages.slice(creationIndex + 1, end)
  };
}
```

## ai context enrichment

### use claude haiku for fast, cheap summarization

claude haiku is perfect for this:
- fast: ~1-2 seconds per issue
- cheap: ~$0.0001 per issue
- good quality for structured extraction

**authentication: reuse claude code oauth token**

no setup required! extract oauth token from claude code:

**macOS:**
```bash
# extract from keychain
security find-generic-password -s "Claude Code-credentials" -w
```

**linux/ubuntu:**
```bash
# read from credentials file
cat ~/.claude/.credentials.json
```

credentials format:
```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "sk-ant-ort01-...",
    "expiresAt": 1748276587173,
    "scopes": ["user:inference", "user:profile"]
  }
}
```

benefits:
- zero setup (uses existing claude code auth)
- uses user's claude pro/max subscription
- no separate api key needed
- token managed by claude code
- same auth as claude code

**token expiration:**

your token expires at: `1760804454572` (unix timestamp in milliseconds)

that's approximately: **~54 days from now** (dec 2025)

access tokens typically expire in 8-12 hours, but refresh happens automatically:
- claude code auto-refreshes using refresh token
- sync daemon should check expiration before each call
- if expired, wait for claude code to refresh or trigger manual refresh

```typescript
async function getClaudeCodeToken() {
  let creds;

  if (process.platform === 'darwin') {
    // macOS - extract from keychain
    const json = execSync(
      'security find-generic-password -s "Claude Code-credentials" -w'
    ).toString();
    creds = JSON.parse(json);
  } else {
    // linux - read from file
    const credsPath = path.join(os.homedir(), '.claude/.credentials.json');
    creds = JSON.parse(fs.readFileSync(credsPath, 'utf8'));
  }

  const oauth = creds.claudeAiOauth;

  // check if token expired
  if (Date.now() >= oauth.expiresAt) {
    throw new Error('claude code token expired - please run claude code to refresh');
  }

  return oauth.accessToken;
}

async function refreshClaudeCodeToken(refreshToken: string) {
  // use claude's oauth refresh endpoint
  const response = await fetch('https://console.anthropic.com/v1/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e'  // claude cli client id
    })
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(`token refresh failed: ${data.error}`);
  }

  // update stored credentials
  const newCreds = {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: Date.now() + (data.expires_in * 1000),
    scopes: data.scope.split(' ')
  };

  // write back to storage
  if (process.platform === 'darwin') {
    // update keychain
    const json = JSON.stringify({ claudeAiOauth: newCreds });
    execSync(`security add-generic-password -U -s "Claude Code-credentials" -w '${json}'`);
  } else {
    // update file
    const credsPath = path.join(os.homedir(), '.claude/.credentials.json');
    fs.writeFileSync(credsPath, JSON.stringify({ claudeAiOauth: newCreds }));
  }

  return newCreds.accessToken;
}

async function enrichIssueContext(issue, contextWindow) {
  const prompt = `
analyze this conversation where an issue was created:

conversation before:
${formatMessages(contextWindow.before)}

issue created:
title: ${issue.title}
body: ${issue.body || 'no description'}

conversation after:
${formatMessages(contextWindow.after)}

extract:
1. detailed summary (what problem is being solved)
2. why this issue was created (rationale)
3. mentioned files/code (relevant context)
4. implementation notes (any technical details discussed)
5. acceptance criteria (what would make this complete)

return as json.
`;

  // reuse claude code oauth token
  const token = await getClaudeCodeToken();
  const anthropic = new Anthropic({ apiKey: token });

  const result = await anthropic.messages.create({
    model: 'claude-3-haiku-20240307',
    max_tokens: 1024,
    messages: [{ role: 'user', content: prompt }]
  });

  const parsed = JSON.parse(result.content[0].text);

  return {
    summary: parsed.summary,
    rationale: parsed.rationale,
    mentioned_files: parsed.mentioned_files,
    implementation_notes: parsed.implementation_notes,
    acceptance_criteria: parsed.acceptance_criteria
  };
}
```

### example enrichment

before context capture:
```json
{
  "id": "bd-42",
  "title": "add rate limiting to api",
  "body": "",
  "session_id": "sess_abc123"
}
```

after context capture:
```json
{
  "id": "bd-42",
  "title": "add rate limiting to api",
  "body": "prevent api abuse by implementing rate limiting",
  "design": "use redis for tracking request counts per user, limit to 100 req/min",
  "acceptance_criteria": "- limit 100 requests per minute per user\n- return 429 when limit exceeded\n- include retry-after header\n- add tests for rate limit behavior",
  "notes": "discussed using redis vs in-memory store, decided on redis for multi-instance support",
  "context_summary": "user reported api getting hammered by one customer, causing slowdowns for others",
  "mentioned_files": ["src/api/middleware/ratelimit.ts", "src/api/index.ts"],
  "session_id": "sess_abc123"
}
```

## storing captured context

### option 1: enrich core fields

use existing issue fields:
```sql
UPDATE issues SET
  body = :enriched_summary,
  design = :implementation_notes,
  acceptance_criteria = :acceptance_criteria,
  notes = :context_notes
WHERE id = :issue_id;
```

### option 2: extension table

store separately for auditability:

```sql
CREATE TABLE beadster_context_capture (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  session_id TEXT,

  -- captured context
  conversation_summary TEXT,
  rationale TEXT,
  mentioned_files TEXT,  -- JSON array
  mentioned_code TEXT,   -- JSON array of snippets
  implementation_notes TEXT,
  suggested_acceptance_criteria TEXT,

  -- metadata
  captured_at INTEGER,
  messages_analyzed INTEGER,
  ai_model TEXT DEFAULT 'claude-3-haiku-20240307',

  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_context_issue ON beadster_context_capture(issue_id);
CREATE INDEX idx_context_session ON beadster_context_capture(session_id);
```

benefit: preserve original user input vs ai-enriched version

## privacy and security

### sensitive data filtering

```typescript
async function sanitizeContext(messages) {
  // remove sensitive patterns
  const sensitivePatterns = [
    /api[_-]?key[:\s=]+[a-zA-Z0-9]+/gi,
    /password[:\s=]+\S+/gi,
    /secret[:\s=]+\S+/gi,
    /token[:\s=]+[a-zA-Z0-9]+/gi
  ];

  return messages.map(m => {
    let content = m.content;
    for (const pattern of sensitivePatterns) {
      content = content.replace(pattern, '[REDACTED]');
    }
    return { ...m, content };
  });
}
```

### user consent

```typescript
// prompt on first use
const consent = await askUser({
  message: "enable context capture for this project?",
  details: "beadster will analyze claude conversation logs to enrich issues with context. logs are processed locally and only summaries sync to cloud.",
  options: ["enable", "disable", "ask each time"]
});

await db.update('sources', sourceId, {
  context_capture: consent === 'enable',
  context_capture_prompt: consent === 'ask each time'
});
```

### opt-out

```typescript
// disable globally
beadster config set context_capture false

// disable per source
beadster source update <source-id> --no-context-capture

// disable per issue (add .no-capture tag)
bd track "add feature" --tags no-capture
```

## sync daemon integration

### context capture in sync flow

```typescript
async function syncIssue(issue) {
  // 1. detect if issue needs context capture
  const needsCapture =
    issue.session_id &&
    !issue.context_captured &&
    source.context_capture;

  if (needsCapture) {
    try {
      // 2. extract conversation context
      const contextWindow = await extractContextWindow(
        issue.session_id,
        issue.created_at
      );

      if (contextWindow) {
        // 3. sanitize sensitive data
        const sanitized = await sanitizeContext([
          ...contextWindow.before,
          contextWindow.creation,
          ...contextWindow.after
        ]);

        // 4. ai enrichment
        const enriched = await enrichIssueContext(issue, {
          before: sanitized.slice(0, -1),
          creation: sanitized[sanitized.length - 1],
          after: []
        });

        // 5. update local issue
        await updateLocalIssue(issue.id, {
          body: enriched.summary,
          design: enriched.implementation_notes,
          acceptance_criteria: enriched.acceptance_criteria,
          notes: enriched.rationale,
          context_captured: true
        });

        // 6. store full context
        await storeContextCapture(issue.id, enriched);
      }
    } catch (err) {
      console.error('context capture failed:', err);
      // continue sync without enrichment
    }
  }

  // 7. sync to cloud
  await syncToCloud(issue);
}
```

### batch processing

for existing issues without context:

```typescript
async function backfillContext(sourceId) {
  const issues = await db.query(`
    SELECT * FROM issues
    WHERE source_id = ?
      AND session_id IS NOT NULL
      AND context_captured = 0
    LIMIT 10
  `, [sourceId]);

  for (const issue of issues) {
    await syncIssue(issue);
    await sleep(1000);  // rate limit ai calls
  }
}
```

## mcp tools

```typescript
tools: [
  'todo_capture_context',     // manually trigger context capture
  'todo_view_context',        // view captured context
  'todo_refresh_context',     // re-run ai enrichment
]
```

examples:

```typescript
// manually capture context for issue
await mcp.call('todo_capture_context', {
  issue_id: 'bd-42'
});

// view captured context
const context = await mcp.call('todo_view_context', {
  issue_id: 'bd-42'
});

// re-run enrichment with larger window
await mcp.call('todo_refresh_context', {
  issue_id: 'bd-42',
  window_size: 30
});
```

## ui views

### issue detail with context

```
bd-42: add rate limiting to api

status: open
priority: P1
assignee: claude-code
created: oct 15, 2024 3:42pm (during claude session)

context summary:
user reported api getting hammered by one customer, causing slowdowns
for others. discussed using redis vs in-memory store for tracking.

implementation notes:
- use redis for request counting (multi-instance support)
- limit 100 requests per minute per user
- return 429 with retry-after header
- middleware in src/api/middleware/ratelimit.ts

acceptance criteria:
✓ limit 100 requests per minute per user
✓ return 429 when limit exceeded
✓ include retry-after header
✓ add tests for rate limit behavior

related files:
- src/api/middleware/ratelimit.ts
- src/api/index.ts
- tests/ratelimit.test.ts

[view full conversation] [refresh context]
```

### context quality indicator

```
bd-42: add rate limiting
📝 rich context captured (25 messages analyzed)

bd-43: fix bug
⚠️ minimal context (created without description)

bd-44: implement feature
📝 context captured (10 messages analyzed)
```

## benefits

- **rich context**: issues have full background and rationale
- **better handoffs**: teammates understand why issue exists
- **implementation guidance**: captured technical decisions
- **acceptance criteria**: auto-generated from conversation
- **file references**: know which files are relevant
- **historical record**: preserve decision-making process
- **agent learning**: future agents can learn from past context
- **search improvement**: better search with full context

## privacy considerations

- logs processed locally on device
- only summaries sync to cloud
- sensitive data filtered automatically
- user consent required
- opt-out available globally or per-issue
- original logs never leave device

## technical challenges

### challenge 1: log format changes

claude may change session log format

**solution**: versioned parsers

```typescript
const logParsers = {
  'v1': parseV1SessionLog,
  'v2': parseV2SessionLog
};

function detectLogVersion(log) {
  if (log.version) return log.version;
  if (log.messages?.[0]?.role) return 'v1';
  return 'unknown';
}
```

### challenge 2: large sessions

some sessions have thousands of messages

**solution**: smart windowing

```typescript
async function findRelevantWindow(session, issueCreatedAt) {
  // find creation message
  const creationIdx = findCreationMessage(session, issueCreatedAt);

  // expand window until we find topic change
  let start = creationIdx;
  let end = creationIdx;

  while (start > 0 && isRelatedTopic(session.messages[start], session.messages[creationIdx])) {
    start--;
  }

  while (end < session.messages.length && isRelatedTopic(session.messages[end], session.messages[creationIdx])) {
    end++;
  }

  return session.messages.slice(start, end + 1);
}
```

### challenge 3: ai costs

enrichment for every issue could be expensive

**solution**: tiered capture

```typescript
const captureLevels = {
  none: { enabled: false },
  basic: { window: 5, ai: false },      // just save messages, no ai
  standard: { window: 10, ai: true },   // ai enrichment, small window
  detailed: { window: 30, ai: true }    // ai enrichment, large window
};

// configure per source
await updateSource(sourceId, {
  context_capture_level: 'standard'
});
```

## future enhancements

- capture screenshots/images from session
- link to specific message in claude ui
- capture file diffs at time of creation
- integrate with git history (what changed around issue creation)
- cross-reference with other issues from same session
- cluster issues by session topic
- suggest related issues based on context similarity
