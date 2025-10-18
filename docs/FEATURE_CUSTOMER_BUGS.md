# customer bug intake

system for accepting bug reports from customers

## overview

let customers report bugs via public form without requiring login

flow:
1. customer fills form on beadster.com/report
2. creates issue with reporter info
3. triage agent reviews automatically
4. human approves/rejects triage
5. accepted bugs go to backlog

## database schema

```sql
-- track customer info
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,  -- which beadster user owns this customer
  email TEXT,
  name TEXT,
  company TEXT,
  external_id TEXT,  -- id from intercom/zendesk if integrated
  created_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- add reporter fields to issues
ALTER TABLE issues ADD COLUMN reporter_type TEXT;   -- 'internal', 'customer', 'agent', 'integration'
ALTER TABLE issues ADD COLUMN reporter_id TEXT;     -- customer_id or user_id
ALTER TABLE issues ADD COLUMN reporter_email TEXT;
ALTER TABLE issues ADD COLUMN reporter_name TEXT;
ALTER TABLE issues ADD COLUMN reported_via TEXT;    -- 'web_form', 'email', 'intercom', 'api'

-- add triage fields
ALTER TABLE issues ADD COLUMN triage_status TEXT;      -- 'new', 'triaged', 'accepted', 'rejected'
ALTER TABLE issues ADD COLUMN triaged_at INTEGER;
ALTER TABLE issues ADD COLUMN triaged_by_user_id TEXT;
ALTER TABLE issues ADD COLUMN triage_notes TEXT;

-- add urgency/impact for prioritization
ALTER TABLE issues ADD COLUMN urgency TEXT;  -- 'low', 'medium', 'high', 'critical'
ALTER TABLE issues ADD COLUMN impact TEXT;   -- 'low', 'medium', 'high'

CREATE INDEX idx_issues_reporter ON issues(reporter_type);
CREATE INDEX idx_issues_triage ON issues(triage_status);
CREATE INDEX idx_customers_email ON customers(email);
```

## public bug report form

### web form

```html
<!-- beadster.com/report -->
<form action="/api/public/issues" method="POST">
  <h2>report a bug</h2>

  <label>your email *</label>
  <input name="email" type="email" required>

  <label>your name</label>
  <input name="name" type="text">

  <label>what happened? *</label>
  <textarea name="description" required></textarea>

  <label>url where bug occurred</label>
  <input name="url" type="url">

  <label>steps to reproduce</label>
  <textarea name="steps"></textarea>

  <label>what did you expect?</label>
  <textarea name="expected"></textarea>

  <button type="submit">submit bug report</button>
</form>
```

### api endpoint

```typescript
// public endpoint - no auth required, rate limited by ip
app.post('/api/public/issues', async (c) => {
  const { email, name, description, url, steps, expected } = await c.req.json();

  // rate limit by ip
  const ip = c.req.header('cf-connecting-ip');
  const rateLimitOk = await checkRateLimit(ip, '10/hour');
  if (!rateLimitOk) {
    return c.json({ error: 'rate limit exceeded' }, 429);
  }

  // find or create customer
  let customer = await db.query(
    'SELECT * FROM customers WHERE email = ?',
    [email]
  );

  if (!customer) {
    customer = await db.insert('customers', {
      id: ulid(),
      email,
      name,
      created_at: Date.now()
    });
  }

  // create issue
  const issue = await db.insert('issues', {
    id: ulid(),
    title: `bug report from ${name || email}`,
    body: formatBugReport({ description, url, steps, expected }),
    status: 'open',
    priority: 2,  // default to medium
    reporter_type: 'customer',
    reporter_id: customer.id,
    reporter_email: email,
    reporter_name: name,
    reported_via: 'web_form',
    triage_status: 'new',
    source_id: 'customer-bugs',
    created_at: Date.now()
  });

  // trigger triage agent
  await triggerAgent('triage', issue.id);

  // send confirmation email to customer
  await sendEmail(email, {
    subject: 'bug report received',
    body: `thanks for reporting! we'll look into it. tracking id: ${issue.id}`
  });

  return c.json({
    id: issue.id,
    message: 'bug report submitted successfully'
  });
});

function formatBugReport({ description, url, steps, expected }) {
  return `
## what happened

${description}

## url

${url || 'not provided'}

## steps to reproduce

${steps || 'not provided'}

## expected behavior

${expected || 'not provided'}
  `.trim();
}
```

## triage workflow

### triage agent

automatically reviews new customer bugs:

```typescript
async function triageAgent(issueId: string) {
  const issue = await db.getIssue(issueId);

  // analyze issue with ai
  const analysis = await analyzeIssue(issue);

  // check for duplicates
  const duplicates = await findDuplicates(issue);

  // suggest classification
  const suggestions = {
    labels: analysis.suggestedLabels,     // ['bug', 'auth', 'critical']
    priority: analysis.suggestedPriority, // 0-4
    urgency: analysis.urgency,            // 'high', 'medium', 'low'
    impact: analysis.impact,              // 'high', 'medium', 'low'
    duplicate_of: duplicates[0]?.id || null,
    reasoning: analysis.reasoning
  };

  // store triage result
  await db.insert('beadster_agent_results', {
    id: ulid(),
    execution_id: executionId,
    result_type: 'triage',
    result_data: JSON.stringify(suggestions),
    created_at: Date.now()
  });

  // update issue with suggestions (not final)
  await db.update('issues', issueId, {
    triage_status: 'triaged',
    triage_notes: suggestions.reasoning
  });

  // notify owner
  await notifyUser(issue.user_id, {
    type: 'new_customer_bug',
    issue_id: issueId,
    suggestions
  });
}

async function analyzeIssue(issue) {
  // use ai to analyze bug report
  const prompt = `
analyze this bug report and suggest:
- urgency level (critical/high/medium/low)
- impact level (high/medium/low)
- priority (0-4)
- labels (bug type, component, etc)
- reasoning

bug report:
${issue.body}
  `;

  const response = await callAI(prompt);
  return parseAIResponse(response);
}

async function findDuplicates(issue) {
  // search for similar issues
  const results = await searchIssues({
    query: issue.title,
    status: ['open', 'in_progress'],
    limit: 5
  });

  // score similarity
  return results
    .map(r => ({
      ...r,
      similarity: calculateSimilarity(issue, r)
    }))
    .filter(r => r.similarity > 0.8)
    .sort((a, b) => b.similarity - a.similarity);
}
```

### human review

```
beadster.com/triage

untriaged bugs (5)

┌─────────────────────────────────────────────────────┐
│ bd-42: bug report from john@example.com             │
│ reported 5 minutes ago via web form                 │
│                                                      │
│ ai analysis:                                        │
│ • urgency: high (user cannot login)                 │
│ • impact: high (affects all users)                  │
│ • suggested priority: P0                            │
│ • suggested labels: bug, auth, critical             │
│ • possible duplicate of: bd-35                      │
│                                                      │
│ reasoning:                                          │
│ "mentions timeout and cannot login - likely auth    │
│  service issue affecting multiple users"            │
│                                                      │
│ [accept as P0] [modify] [mark duplicate] [reject]   │
└─────────────────────────────────────────────────────┘
```

### accept/reject actions

```typescript
// accept triage suggestions
POST /api/issues/:id/triage/accept
{
  "priority": 0,
  "labels": ["bug", "auth", "critical"],
  "urgency": "high",
  "impact": "high"
}

// mark as duplicate
POST /api/issues/:id/triage/duplicate
{
  "duplicate_of": "bd-35"
}

// reject (close with reason)
POST /api/issues/:id/triage/reject
{
  "reason": "not a bug, user error",
  "reply_to_customer": "please check your password is correct"
}
```

## customer communication

### auto-reply on status changes

```typescript
async function onIssueStatusChange(issue, oldStatus, newStatus) {
  if (issue.reporter_type !== 'customer') return;

  const messages = {
    triaged: `we've reviewed your bug report and added it to our backlog.`,
    in_progress: `we're working on fixing this issue.`,
    closed: `this issue has been resolved. please let us know if you still see problems.`
  };

  const message = messages[newStatus];
  if (!message) return;

  await sendEmail(issue.reporter_email, {
    subject: `update on your bug report (${issue.id})`,
    body: message
  });
}
```

## customer dashboard

optional: let customers track their reports

```
beadster.com/track?email=john@example.com&id=bd-42

your bug report: bd-42

status: in progress
priority: P0
reported: 1 hour ago
last update: 5 minutes ago

timeline:
• 1 hour ago - report submitted
• 55 minutes ago - triaged as P0
• 5 minutes ago - started working on fix

we'll email you when this is resolved.
```

## integration with support tools

### intercom

sync customer messages to beadster:

```typescript
// webhook from intercom
app.post('/api/webhooks/intercom', async (c) => {
  const { type, data } = await c.req.json();

  if (type === 'conversation.user.created') {
    // customer sent message
    await createCustomerIssue({
      email: data.user.email,
      name: data.user.name,
      description: data.conversation_parts[0].body,
      external_id: data.conversation.id,
      reported_via: 'intercom'
    });
  }

  return c.json({ ok: true });
});
```

### zendesk

similar webhook integration

## analytics

track customer bug metrics:

```sql
-- bugs by status
SELECT triage_status, COUNT(*)
FROM issues
WHERE reporter_type = 'customer'
GROUP BY triage_status;

-- response time
SELECT AVG(triaged_at - created_at) as avg_triage_time
FROM issues
WHERE reporter_type = 'customer' AND triaged_at IS NOT NULL;

-- resolution time
SELECT AVG(closed_at - created_at) as avg_resolution_time
FROM issues
WHERE reporter_type = 'customer' AND status = 'closed';

-- top reporters
SELECT reporter_email, COUNT(*) as bug_count
FROM issues
WHERE reporter_type = 'customer'
GROUP BY reporter_email
ORDER BY bug_count DESC
LIMIT 10;
```

## benefits

- **no account needed** - customers can report bugs easily
- **automatic triage** - ai does initial classification
- **duplicate detection** - avoid duplicate work
- **customer updates** - auto-notify on status changes
- **prioritization** - urgency + impact guide priority
- **integration ready** - works with intercom/zendesk
- **analytics** - track customer satisfaction

## security considerations

- rate limiting by ip (prevent spam)
- email validation
- content filtering (check for spam/abuse)
- captcha for public form (optional)
- sanitize inputs (prevent xss)
