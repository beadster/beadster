# assignment and responsibility

who is responsible for completing each task

## overview

beadster supports assignment to track who should work on each issue:
- assign to humans (you, teammates)
- assign to agents (claude code, research agent, qa agent)
- assign to external systems (ci/cd, scheduled jobs)
- unassigned tasks go to default assignee or stay in pool

## database field

already part of core beads schema:

```sql
-- in issues table
assignee TEXT
```

stored as simple string identifier:
- human: email or name ("anton@example.com", "anton")
- agent: agent identifier ("claude-code", "research-agent", "qa-bot")
- system: system name ("github-actions", "cron")
- null: unassigned (anyone can pick up)

## use cases

### manual tasks vs agent tasks

```typescript
// claude code working on implementation
{
  title: "implement user registration api",
  assignee: "claude-code",
  status: "in_progress",
  labels: ["backend", "api"]
}

// manual testing task
{
  title: "test registration flow on mobile",
  assignee: "anton@example.com",
  status: "open",
  labels: ["qa", "manual"]
}

// research task for research agent
{
  title: "research: graphql vs rest for this use case",
  assignee: "research-agent",
  status: "open",
  labels: ["research"]
}
```

### team assignment

```typescript
// assign to teammate
{
  title: "design user profile page",
  assignee: "sarah@example.com",
  priority: 1
}

// assign to self
{
  title: "review pull request #123",
  assignee: "anton@example.com",
  due_at: Date.now() + 86400000  // tomorrow
}
```

### auto-assignment rules

when creating issues, auto-assign based on rules:

```typescript
// by label
if (issue.labels.includes('research')) {
  issue.assignee = 'research-agent';
}

// by reporter type
if (issue.reporter_type === 'customer') {
  issue.assignee = 'triage-agent';
}

// by source
if (issue.source_id === 'backend-repo') {
  issue.assignee = 'backend-team';
}

// by type
if (issue.issue_type === 'bug' && issue.priority === 0) {
  issue.assignee = 'on-call-dev';
}
```

### round-robin assignment

distribute work evenly:

```typescript
const team = ['alice@ex.com', 'bob@ex.com', 'charlie@ex.com'];
let nextIndex = 0;

function assignNextInQueue() {
  const assignee = team[nextIndex];
  nextIndex = (nextIndex + 1) % team.length;
  return assignee;
}

// new customer bug
{
  title: "login not working",
  assignee: assignNextInQueue(),  // alice
  reporter_type: "customer"
}
```

## filtering by assignee

### my work view

```sql
SELECT * FROM issues
WHERE assignee = 'anton@example.com'
  AND status IN ('open', 'in_progress')
ORDER BY priority ASC, due_at ASC;
```

### agent work queue

```sql
SELECT * FROM ready_issues
WHERE assignee = 'claude-code'
  AND status = 'open'
ORDER BY priority ASC
LIMIT 1;  -- next task for agent
```

### unassigned work

```sql
SELECT * FROM ready_issues
WHERE assignee IS NULL
  OR assignee = ''
ORDER BY priority ASC, created_at ASC;
```

### team view

```sql
SELECT
  assignee,
  COUNT(*) as issue_count,
  SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress,
  SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) as todo
FROM issues
WHERE assignee IN ('alice@ex.com', 'bob@ex.com', 'charlie@ex.com')
  AND status != 'closed'
GROUP BY assignee;
```

## assignment workflows

### claiming work

developer picks up unassigned task:

```typescript
// before
{
  id: "bd-42",
  title: "fix login bug",
  assignee: null,
  status: "open"
}

// developer claims it
PATCH /api/issues/bd-42
{
  "assignee": "anton@example.com",
  "status": "in_progress"
}
```

### reassignment

move task to someone else:

```typescript
// was assigned to alice, reassign to bob
PATCH /api/issues/bd-50
{
  "assignee": "bob@example.com"
}

// create event for audit trail
{
  event_type: "reassigned",
  old_value: { assignee: "alice@ex.com" },
  new_value: { assignee: "bob@ex.com" }
}
```

### delegation

create subtask and assign:

```typescript
// parent task
{
  id: "bd-10",
  title: "user authentication system",
  assignee: "tech-lead",
  issue_type: "epic"
}

// delegate subtasks
{
  id: "bd-11",
  title: "design auth database schema",
  assignee: "alice@ex.com",
  parent: "bd-10"  // parent-child dependency
}

{
  id: "bd-12",
  title: "implement oauth integration",
  assignee: "bob@ex.com",
  parent: "bd-10"
}
```

## agent coordination

### agent picks next task

```typescript
// claude code agent looking for work
const nextTask = await db.query(`
  SELECT * FROM ready_issues
  WHERE assignee = 'claude-code'
    AND status = 'open'
  ORDER BY priority ASC, due_at ASC
  LIMIT 1
`);

if (!nextTask) {
  // no assigned work, check unassigned pool
  const unassigned = await db.query(`
    SELECT * FROM ready_issues
    WHERE (assignee IS NULL OR assignee = '')
      AND labels LIKE '%code%'  -- only code tasks
      AND status = 'open'
    ORDER BY priority ASC
    LIMIT 1
  `);
}
```

### agent creates subtasks

```typescript
// claude working on bd-5, discovers more work
{
  id: "bd-15",
  title: "add rate limiting",
  assignee: "claude-code",  // assign to self
  discovered_from: "bd-5",
  status: "open"
}

{
  id: "bd-16",
  title: "test rate limiting manually",
  assignee: "anton@example.com",  // assign to human for testing
  discovered_from: "bd-5",
  status: "open"
}
```

### multiple agents working

```typescript
// triage agent processes customer bugs
{
  title: "cannot login",
  assignee: "triage-agent",
  reporter_type: "customer",
  triage_status: "new"
}

// after triage, reassign to dev
{
  title: "cannot login",
  assignee: "backend-team",
  triage_status: "triaged",
  priority: 0,
  labels: ["bug", "auth", "p0"]
}
```

## ui views

### my tasks

```
beadster.com/my

my tasks (5)

filter by: [status ▼] [priority ▼] [source ▼]

in progress (2)
- [P0] bd-42: fix auth bug (due in 2 hours)
- [P1] bd-50: implement api endpoint (no deadline)

open (3)
- [P1] bd-51: test mobile app manually
- [P2] bd-52: review design docs
- [P2] bd-53: update api documentation
```

### team dashboard

```
beadster.com/team

team workload

alice@example.com (4 tasks)
- 2 in progress
- 2 open

bob@example.com (6 tasks)
- 1 in progress
- 5 open

charlie@example.com (2 tasks)
- 0 in progress
- 2 open

unassigned (8 tasks)
- 3 ready to work
- 5 blocked
```

### agent queue

```
beadster.com/agents/claude-code

claude-code queue (3)

current (1)
- bd-42: implement user registration (in progress, 45 min)

next (2)
- bd-15: add rate limiting (ready)
- bd-20: refactor auth module (ready)
```

## mcp tools

```typescript
tools: [
  'todo_assign',      // assign issue to someone
  'todo_claim',       // claim unassigned issue
  'todo_my_tasks',    // list my assigned tasks
  'todo_unassigned',  // list unassigned ready work
  'todo_team',        // show team workload
]
```

examples:

```typescript
// assign issue
await mcp.call('todo_assign', {
  issue_id: 'bd-42',
  assignee: 'anton@example.com'
});

// claim unassigned issue
await mcp.call('todo_claim', {
  issue_id: 'bd-50'
});

// list my tasks
const myTasks = await mcp.call('todo_my_tasks', {
  status: 'open',
  limit: 10
});

// list unassigned work
const available = await mcp.call('todo_unassigned', {
  labels: ['backend'],
  limit: 5
});
```

## api endpoints

```typescript
// assign issue
PATCH /api/issues/:id
{
  "assignee": "anton@example.com"
}

// get my assigned tasks
GET /api/issues?assignee=me&status=open,in_progress

// get unassigned work
GET /api/issues?assignee=null&status=open

// get team workload
GET /api/team/workload
```

## notifications

notify assignee when:
- new issue assigned to them
- issue reassigned to them
- their issue blocked by something
- their issue due soon
- their issue overdue

```typescript
async function notifyAssignment(issue) {
  if (!issue.assignee) return;

  await sendNotification(issue.assignee, {
    type: 'issue_assigned',
    issue_id: issue.id,
    title: issue.title,
    priority: issue.priority,
    due_at: issue.due_at
  });
}
```

## benefits

- **clear ownership**: know who's responsible for what
- **workload visibility**: see team capacity and balance
- **agent coordination**: multiple agents work on different tasks
- **human + agent**: mix automated and manual work
- **accountability**: track who did what via events table
- **flexible assignment**: assign to individuals, teams, or agents
- **smart routing**: auto-assign based on rules and patterns
