# due dates and deadlines

time-based tracking for issues

## database fields

```sql
ALTER TABLE issues ADD COLUMN due_at INTEGER;        -- unix timestamp
ALTER TABLE issues ADD COLUMN due_time_zone TEXT;    -- 'America/New_York', 'UTC', etc
ALTER TABLE issues ADD COLUMN remind_at INTEGER;     -- when to send reminder
ALTER TABLE issues ADD COLUMN reminded BOOLEAN DEFAULT 0;

CREATE INDEX idx_issues_due ON issues(due_at);
CREATE INDEX idx_issues_remind ON issues(remind_at) WHERE reminded = 0;
```

## use cases

### personal deadlines

```typescript
// create issue with deadline
{
  title: "submit tax return",
  due_at: 1713484800,  // april 15, 2024 midnight
  priority: 0
}

// urgent deadline (today)
{
  title: "fix production bug",
  due_at: Date.now() + 3600000,  // 1 hour from now
  urgency: "critical"
}
```

### customer sla

```typescript
// P0 customer bug - respond in 1 hour, resolve in 4 hours
{
  title: "customer cannot login",
  reporter_type: "customer",
  priority: 0,
  due_at: Date.now() + (4 * 3600000),  // 4 hours
  urgency: "critical"
}
```

### sprint/cycle deadlines

```typescript
// task in current sprint
{
  title: "implement user profile",
  cycle_id: "sprint-24",
  due_at: 1713484800,  // end of sprint
  priority: 1
}
```

## sorting by urgency

combine due date with priority for smart sorting:

```typescript
function calculateUrgencyScore(issue) {
  if (!issue.due_at) return issue.priority * 1000;

  const hoursUntilDue = (issue.due_at - Date.now()) / 3600000;

  if (hoursUntilDue < 0) {
    // overdue - highest priority
    return -Math.abs(hoursUntilDue) * 100;
  }

  if (hoursUntilDue < 24) {
    // due today - very urgent
    return hoursUntilDue * 10;
  }

  // normal - combine with priority
  return issue.priority * 1000 + hoursUntilDue;
}
```

sorted query:

```sql
SELECT *,
  CASE
    WHEN due_at IS NULL THEN priority * 1000
    WHEN due_at < unixepoch('now') THEN -((unixepoch('now') - due_at) / 3600)
    WHEN due_at < unixepoch('now', '+1 day') THEN (due_at - unixepoch('now')) / 3600
    ELSE priority * 1000 + (due_at - unixepoch('now')) / 3600
  END as urgency_score
FROM issues
WHERE status = 'open'
ORDER BY urgency_score ASC;
```

result:
```
overdue issues first (negative score)
due today next (0-24)
then by priority + time remaining
```

## reminders

### set reminder before due date

```typescript
// due april 15, remind april 10
{
  due_at: 1713484800,      // april 15
  remind_at: 1713052800,   // april 10 (5 days before)
  reminded: false
}
```

### reminder daemon

runs every hour:

```typescript
async function checkReminders() {
  const now = Date.now();

  // find issues that need reminders
  const issues = await db.query(`
    SELECT * FROM issues
    WHERE remind_at <= ?
      AND reminded = 0
      AND status IN ('open', 'in_progress')
  `, [now]);

  for (const issue of issues) {
    // send notification
    await notifyUser(issue.user_id, {
      type: 'due_date_reminder',
      issue_id: issue.id,
      title: issue.title,
      due_at: issue.due_at,
      hours_remaining: (issue.due_at - now) / 3600000
    });

    // mark as reminded
    await db.update('issues', issue.id, { reminded: true });
  }
}
```

### auto-set reminder

```typescript
// when setting due date, auto-calculate reminder
function autoSetReminder(due_at: number) {
  const hoursUntilDue = (due_at - Date.now()) / 3600000;

  if (hoursUntilDue <= 24) {
    // due today - remind 1 hour before
    return due_at - 3600000;
  }

  if (hoursUntilDue <= 168) {
    // due this week - remind 1 day before
    return due_at - (24 * 3600000);
  }

  // due later - remind 1 week before
  return due_at - (7 * 24 * 3600000);
}
```

## overdue handling

### mark overdue issues

```sql
-- view of overdue issues
CREATE VIEW overdue_issues AS
SELECT *,
  (unixepoch('now') - due_at) / 3600 as hours_overdue
FROM issues
WHERE status IN ('open', 'in_progress')
  AND due_at < unixepoch('now')
ORDER BY hours_overdue DESC;
```

### auto-escalate overdue

```typescript
// run daily
async function escalateOverdue() {
  const overdue = await db.query(`
    SELECT * FROM overdue_issues
    WHERE hours_overdue > 24
  `);

  for (const issue of overdue) {
    // increase priority
    if (issue.priority < 4) {
      await db.update('issues', issue.id, {
        priority: Math.max(0, issue.priority - 1),
        labels: [...issue.labels, 'overdue']
      });
    }

    // notify owner
    await notifyUser(issue.user_id, {
      type: 'issue_overdue',
      issue_id: issue.id,
      hours_overdue: issue.hours_overdue
    });
  }
}
```

## ui views

### calendar view

```
beadster.com/calendar

october 2024

sun  mon  tue  wed  thu  fri  sat
         1    2    3    4    5
     bd-42  bd-15

6    7    8    9    10   11   12
              bd-50

13   14   15   16   17   18   19
                         bd-23
                         bd-24
                         bd-25

bd-42: submit tax return (overdue 3 days)
bd-15: finish api docs (due oct 2)
bd-50: code review (due oct 9)
bd-23, bd-24, bd-25: sprint 24 tasks (due oct 18)
```

### today view

```
beadster.com/today

overdue (2)
- bd-42: submit tax return (3 days overdue)
- bd-15: finish api docs (1 day overdue)

due today (3)
- bd-50: code review (in 4 hours)
- bd-51: fix critical bug (in 2 hours)
- bd-52: update docs (tonight)

due this week (5)
- bd-23: implement user profile (oct 18)
- bd-24: add tests (oct 18)
- bd-25: deploy to staging (oct 18)
- bd-30: review design (oct 16)
- bd-31: update dependencies (oct 17)
```

### issue detail

```
bd-42: submit tax return

status: open
priority: P0
due: april 15, 2024 (3 days overdue!)
created: march 1, 2024
reminder: sent april 10

[mark complete] [extend deadline] [snooze]
```

## mcp tools

```typescript
tools: [
  'todo_set_due',      // set due date for issue
  'todo_due_today',    // list issues due today
  'todo_overdue',      // list overdue issues
  'todo_upcoming',     // list issues due soon
  'todo_snooze',       // postpone due date
]
```

example:

```typescript
// set due date
await mcp.call('todo_set_due', {
  issue_id: 'bd-42',
  due_at: '2024-04-15',  // or unix timestamp
  remind_days_before: 5
});

// list overdue
const overdue = await mcp.call('todo_overdue', {
  limit: 10
});
```

## api endpoints

```typescript
// set due date
PATCH /api/issues/:id
{
  "due_at": 1713484800,
  "remind_at": 1713052800
}

// get issues due today
GET /api/issues?due=today

// get overdue issues
GET /api/issues?overdue=true

// get due this week
GET /api/issues?due_before=7d
```

## time zone handling

store in utc, display in user's timezone:

```typescript
// when creating issue
{
  due_at: 1713484800,           // utc timestamp
  due_time_zone: 'America/New_York'  // user's timezone
}

// when displaying
function displayDueDate(issue, userTimeZone) {
  const date = new Date(issue.due_at * 1000);
  return date.toLocaleString('en-US', {
    timeZone: userTimeZone || issue.due_time_zone,
    dateStyle: 'medium',
    timeStyle: 'short'
  });
}
```

## natural language parsing

let users set due dates naturally:

```typescript
// agent understands natural language
"add todo: submit taxes, due april 15"
→ due_at: timestamp for april 15

"fix bug asap, due in 2 hours"
→ due_at: now + 2 hours

"implement feature by end of sprint"
→ due_at: current sprint end date

"review pr tomorrow"
→ due_at: tomorrow at 9am
```

parser:

```typescript
function parseDueDate(text: string): number | null {
  const patterns = {
    'tomorrow': () => startOfDay(addDays(new Date(), 1)),
    'today': () => endOfDay(new Date()),
    'next week': () => startOfDay(addWeeks(new Date(), 1)),
    'in (\\d+) hours?': (match) => addHours(new Date(), parseInt(match[1])),
    'in (\\d+) days?': (match) => addDays(new Date(), parseInt(match[1])),
    '(\\d{4})-(\\d{2})-(\\d{2})': (match) => new Date(match[0])
  };

  for (const [pattern, fn] of Object.entries(patterns)) {
    const match = text.match(new RegExp(pattern, 'i'));
    if (match) {
      return fn(match).getTime() / 1000;
    }
  }

  return null;
}
```

## recurring deadlines

for repeating tasks:

```sql
ALTER TABLE issues ADD COLUMN recurrence TEXT;  -- 'daily', 'weekly', 'monthly'
ALTER TABLE issues ADD COLUMN recurrence_end INTEGER;  -- when to stop
```

example:

```typescript
{
  title: "send weekly report",
  due_at: nextFriday(),
  recurrence: "weekly",
  recurrence_end: endOfYear()
}

// when marked complete, auto-create next occurrence
async function onComplete(issue) {
  if (!issue.recurrence) return;

  const nextDue = calculateNextDue(issue.due_at, issue.recurrence);

  if (nextDue <= issue.recurrence_end) {
    await createIssue({
      ...issue,
      id: ulid(),
      due_at: nextDue,
      status: 'open',
      completed_at: null
    });
  }
}
```

## integration with cycles

link due dates to sprint/cycle:

```typescript
// when adding to cycle, auto-set due date
{
  title: "implement feature",
  cycle_id: "sprint-24",
  due_at: getCycleEndDate("sprint-24")  // auto-set to cycle end
}
```

## benefits

- **time awareness**: know what's urgent vs important
- **never miss deadlines**: reminders keep you on track
- **smart prioritization**: overdue issues auto-escalate
- **visibility**: calendar and today views show timeline
- **customer sla**: auto-track response/resolution times
- **natural language**: set dates easily ("due tomorrow")
- **recurring tasks**: handle weekly reports, monthly reviews
