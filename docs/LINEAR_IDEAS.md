# linear concepts to consider

ideas from linear's approach to issue tracking and ai agents

## from linear docs

based on what we know linear has:
- mcp server for ai agent access
- triage system
- integrations with customer support tools (intercom, zendesk, front)
- teams and projects
- cycles (sprint-like)
- rich issue properties

## concepts to adopt

### 1. triage workflow

linear has good triage for incoming issues

our implementation:
- `triage_status`: new → triaged → accepted/rejected
- triage agent reviews new issues
- human approves triage suggestions
- accepted issues move to backlog

benefits:
- handle customer bug reports
- classify incoming work
- reduce noise in backlog
- agent does initial filtering

### 2. issue views

multiple ways to view same data

ideas:
- inbox view: all new/untriaged
- backlog view: accepted, not started
- active view: in progress
- ready view: no blockers
- by team/source
- by cycle/milestone

### 3. public issue submission

let customers report bugs without login

```typescript
// public endpoint (no auth, rate limited by ip)
POST /api/public/issues
{
  "email": "customer@example.com",
  "name": "john doe",
  "title": "cannot login",
  "description": "getting timeout error",
  "url": "https://myapp.com/login"
}
```

creates issue with:
- reporter_type: 'customer'
- triage_status: 'new'
- source_id: 'customer-bugs'

triggers triage agent automatically

### 4. integration as reporter

track which integration created issue

```sql
ALTER TABLE issues ADD COLUMN integration_source TEXT;  -- 'intercom', 'zendesk', 'sentry', 'github'
ALTER TABLE issues ADD COLUMN integration_id TEXT;      -- external id from that system
```

use cases:
- sentry error → auto-create issue
- intercom message → create support issue
- github issue → sync to beadster
- zendesk ticket → track in beadster

### 5. bi-directional sync

sync beadster issues back to external systems

example: github issues
- create issue in beadster → create in github
- update in beadster → update in github
- close in beadster → close in github

example: linear-style
- customer reports in intercom
- auto-creates beadster issue
- triage agent classifies
- dev fixes and closes in beadster
- auto-replies to customer in intercom

### 6. team assignment

if multiple people use beadster

```sql
CREATE TABLE teams (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,  -- team owner
  name TEXT,
  description TEXT,
  created_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE team_members (
  team_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT,  -- 'owner', 'member', 'viewer'
  PRIMARY KEY (team_id, user_id),
  FOREIGN KEY (team_id) REFERENCES teams(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

ALTER TABLE issues ADD COLUMN team_id TEXT;
ALTER TABLE issues ADD COLUMN assigned_to_user_id TEXT;
```

### 7. cycles/milestones

group issues by time period

```sql
CREATE TABLE cycles (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT,
  start_date INTEGER,
  end_date INTEGER,
  status TEXT,  -- 'planned', 'active', 'completed'
  FOREIGN KEY (user_id) REFERENCES users(id)
);

ALTER TABLE issues ADD COLUMN cycle_id TEXT;
```

use cases:
- sprint planning
- monthly goals
- release planning

### 8. estimates and tracking

track time

```sql
ALTER TABLE issues ADD COLUMN estimate_minutes INTEGER;
ALTER TABLE issues ADD COLUMN actual_minutes INTEGER;
ALTER TABLE issues ADD COLUMN started_at INTEGER;
ALTER TABLE issues ADD COLUMN completed_at INTEGER;
```

calculate:
- velocity (completed points per cycle)
- accuracy (estimate vs actual)
- throughput (issues per week)

### 9. issue templates

predefined templates for common issue types

```sql
CREATE TABLE issue_templates (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT,
  title_template TEXT,
  body_template TEXT,
  default_labels TEXT,  -- JSON array
  default_priority INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
```

example templates:
- bug report
- feature request
- customer issue
- research task

### 10. automation rules

linear-style automations

```sql
CREATE TABLE automations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT,
  trigger TEXT,      -- 'issue_created', 'status_changed', 'label_added'
  conditions TEXT,   -- JSON
  actions TEXT,      -- JSON
  enabled BOOLEAN DEFAULT 1,
  FOREIGN KEY (user_id) REFERENCES users(id)
);
```

example:
```json
{
  "trigger": "issue_created",
  "conditions": {
    "reporter_type": "customer",
    "labels_include": ["bug"]
  },
  "actions": [
    {"type": "set_priority", "value": 1},
    {"type": "add_label", "value": "needs-triage"},
    {"type": "trigger_agent", "value": "triage"}
  ]
}
```

### 11. sla tracking

for customer issues

```sql
ALTER TABLE issues ADD COLUMN sla_due_at INTEGER;
ALTER TABLE issues ADD COLUMN sla_breached BOOLEAN DEFAULT 0;
```

rules:
- P0: respond in 1 hour, resolve in 4 hours
- P1: respond in 4 hours, resolve in 24 hours
- P2: respond in 24 hours, resolve in 7 days

auto-escalate if sla breached

### 12. issue relationships beyond dependencies

```sql
CREATE TABLE issue_relations (
  issue_id TEXT NOT NULL,
  related_issue_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,  -- 'duplicate', 'similar', 'caused-by', 'causes'
  PRIMARY KEY (issue_id, related_issue_id),
  FOREIGN KEY (issue_id) REFERENCES issues(id),
  FOREIGN KEY (related_issue_id) REFERENCES issues(id)
);
```

use cases:
- mark duplicates
- track causality (this bug caused that bug)
- find similar issues

## what to implement now vs later

### now (mvp)

priority for initial release:
- triage workflow (new → triaged → accepted)
- public issue submission
- basic team support (assignee field)
- issue templates

### later (post-mvp)

nice to have:
- cycles/milestones
- bi-directional sync with github/linear
- automation rules
- sla tracking
- advanced analytics

### maybe (if needed)

depends on usage:
- multiple teams per user
- time tracking
- custom fields
- complex workflows

## implementation priority

1. **triage system** - needed for customer bug intake
2. **public submission** - let customers report issues
3. **basic templates** - speed up issue creation
4. **team assignment** - if >1 person using beadster

later:
5. cycles - if using for sprint planning
6. automations - if repetitive tasks emerge
7. integrations - if using with sentry/intercom/etc

## key differences from linear

linear is for **teams**, beadster is for **individuals + ai agents**

linear focuses on:
- collaboration
- project management
- team workflows

beadster focuses on:
- ai agent workflows
- personal productivity
- sync across devices
- offline-first with local .beads/

we should:
- keep it simple
- focus on agent integration
- support solo dev first
- add team features if needed
