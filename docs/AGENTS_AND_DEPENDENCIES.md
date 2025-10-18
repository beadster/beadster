# agents and dependencies

beadster's agent system and four dependency types (from beads)

## four dependency types

following beads design, beadster supports four relationship types:

### 1. blocks (hard dependency)

issue X **must** be completed before issue Y can start

```sql
INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES ('bd-2', 'bd-1', 'blocks');
-- bd-2 is blocked by bd-1
-- bd-2 won't appear in ready_issues until bd-1 is closed
```

use cases:
- "implement api" blocks "build ui" (ui needs api endpoints)
- "database schema" blocks "create models" (need schema first)
- "fix critical bug" blocks "deploy to production" (bug must be fixed)

affects **ready work queue** - only unblocked issues show up

### 2. related (soft relationship)

issues are connected but don't block each other

```sql
INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES ('bd-5', 'bd-3', 'related');
-- bd-5 and bd-3 are related
-- both can be worked on independently
```

use cases:
- "add dark mode" related to "update theme system"
- "optimize queries" related to "add caching"
- "write docs" related to "implement feature" (can happen in parallel)

does **not** affect ready work queue

### 3. parent-child (hierarchy)

epic contains subtasks

```sql
-- create epic
INSERT INTO issues (id, title, issue_type) VALUES ('bd-10', 'auth system', 'epic');

-- create subtasks
INSERT INTO issues (id, title) VALUES ('bd-11', 'user registration');
INSERT INTO issues (id, title) VALUES ('bd-12', 'user login');
INSERT INTO issues (id, title) VALUES ('bd-13', 'password reset');

-- link to epic
INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES
  ('bd-11', 'bd-10', 'parent-child'),
  ('bd-12', 'bd-10', 'parent-child'),
  ('bd-13', 'bd-10', 'parent-child');
```

use cases:
- organize large features into smaller tasks
- track progress on epics (3/5 subtasks done)
- filter by epic

does **not** affect ready work queue (subtasks can be worked independently)

### 4. discovered-from (provenance)

track issues discovered while working on other issues

```sql
-- working on bd-5, discovered bd-15
INSERT INTO issues (id, title) VALUES ('bd-15', 'add rate limiting');

INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES ('bd-15', 'bd-5', 'discovered-from');
-- bd-15 was discovered while working on bd-5
```

use cases:
- agent discovers bugs while implementing feature
- find todos/fixmes in code
- track technical debt discovered during work
- see what new work emerged from completed work

does **not** affect ready work queue

benefits:
- see what issues spawned other issues
- understand how backlog grows
- track productivity (completed 1 issue, discovered 3 more)

## ready work algorithm

```sql
-- issues with NO open blockers
SELECT i.*
FROM issues i
WHERE i.status = 'open'
  AND NOT EXISTS (
    SELECT 1 FROM dependencies d
    JOIN issues blocker ON d.depends_on_id = blocker.id
    WHERE d.issue_id = i.id
      AND d.type = 'blocks'  -- only blocks type affects ready work
      AND blocker.status IN ('open', 'in_progress', 'blocked')
  )
ORDER BY i.priority ASC, i.created_at ASC;
```

only `blocks` dependencies prevent an issue from being ready

## agent system

generic agent execution framework

### agent types

agents are configurable, not hardcoded:

```typescript
const agentTypes = {
  triage: {
    triggers: ['new_issue'],
    filters: { reporter_type: 'customer', triage_status: 'new' },
    actions: ['classify', 'set_priority', 'assign_team']
  },

  research: {
    triggers: ['label_added'],
    filters: { labels: ['research'], status: 'ready' },
    actions: ['web_search', 'read_docs', 'summarize']
  },

  code_review: {
    triggers: ['status_change'],
    filters: { status: 'in_progress', has_pr: true },
    actions: ['review_code', 'suggest_improvements', 'check_tests']
  },

  qa: {
    triggers: ['status_change'],
    filters: { status: 'ready_for_qa' },
    actions: ['run_tests', 'check_coverage', 'report_issues']
  }
};
```

### execution flow

```
1. trigger event occurs (new issue, status change, etc)
   ↓
2. check which agents match trigger + filters
   ↓
3. create execution record in beadster_executions
   ↓
4. agent runs actions
   ↓
5. store results in beadster_agent_results
   ↓
6. update issue based on agent output
   ↓
7. mark execution as completed
```

### database schema

```sql
-- track agent executions
CREATE TABLE beadster_executions (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  agent_type TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at INTEGER,
  completed_at INTEGER,
  error TEXT,
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

-- store agent outputs (generic JSON)
CREATE TABLE beadster_agent_results (
  id TEXT PRIMARY KEY,
  execution_id TEXT NOT NULL,
  result_type TEXT NOT NULL,
  result_data TEXT NOT NULL,  -- JSON
  created_at INTEGER,
  FOREIGN KEY (execution_id) REFERENCES beadster_executions(id) ON DELETE CASCADE
);
```

### agent result examples

#### triage agent

```json
{
  "agent_type": "triage",
  "result_type": "classification",
  "result_data": {
    "suggested_labels": ["bug", "auth", "p1"],
    "suggested_priority": 1,
    "suggested_assignee": "backend-team",
    "duplicate_of": null,
    "confidence": 0.85,
    "reasoning": "mentions 'cannot login' and 'timeout' - likely auth bug"
  }
}
```

#### research agent

```json
{
  "agent_type": "research",
  "result_type": "research_findings",
  "result_data": {
    "topic": "graphql vs rest api",
    "findings": "## Summary\nGraphQL provides...\n",
    "sources": [
      "https://graphql.org/learn/",
      "https://www.howtographql.com/"
    ],
    "recommendation": "use graphql for flexible queries",
    "confidence": 0.9
  }
}
```

#### code review agent

```json
{
  "agent_type": "code_review",
  "result_type": "review",
  "result_data": {
    "pr_url": "https://github.com/user/repo/pull/123",
    "files_reviewed": 5,
    "issues_found": [
      {
        "file": "src/auth.ts",
        "line": 42,
        "severity": "high",
        "issue": "missing error handling",
        "suggestion": "wrap in try-catch"
      }
    ],
    "overall_score": 7.5,
    "approve": false,
    "reasoning": "needs error handling improvements"
  }
}
```

#### qa agent

```json
{
  "agent_type": "qa",
  "result_type": "test_results",
  "result_data": {
    "tests_run": 42,
    "tests_passed": 40,
    "tests_failed": 2,
    "coverage": 85.3,
    "failures": [
      {
        "test": "auth.test.ts > login with invalid password",
        "error": "expected 401, got 500"
      }
    ],
    "pass": false
  }
}
```

## workflows

### triage workflow

```
customer reports bug via web form
  ↓
create issue:
  - reporter_type: 'customer'
  - triage_status: 'new'
  - source_id: 'customer-bugs'
  ↓
triage agent triggered:
  - checks for duplicates
  - classifies (bug/feature/question)
  - suggests labels
  - sets urgency/impact
  - suggests assignee
  ↓
stores result in beadster_agent_results
  ↓
human reviews triage suggestions:
  - accept → apply suggestions, set triage_status: 'triaged'
  - modify → adjust and set triage_status: 'triaged'
  - reject → close with reason
  ↓
triaged issues move to backlog
```

### research workflow

```
dev creates issue:
  - title: "research: graphql vs rest"
  - labels: ["research", "api"]
  - status: "open"
  ↓
check ready work:
  - no blockers? yes
  - has label "research"? yes
  ↓
research agent triggered:
  - reads issue title/body for questions
  - searches web for comparisons
  - reads documentation
  - summarizes findings
  - makes recommendation
  ↓
stores result in beadster_agent_results
  ↓
adds comment to issue with findings
  ↓
sets status: "completed"
  ↓
dev reviews findings and makes decision
```

### auto-discovery workflow

```
agent working on issue bd-5
  ↓
notices TODO comment in code:
  // TODO: add rate limiting to prevent abuse
  ↓
creates new issue bd-15:
  - title: "add rate limiting to api"
  - labels: ["todo", "security"]
  - discovered-from: bd-5
  ↓
adds dependency:
  - bd-15 discovered-from bd-5
  ↓
continues working on bd-5
  ↓
closes bd-5
  ↓
bd-15 now in backlog for future work
```

### code review workflow

```
dev creates PR #123
  ↓
updates issue:
  - git_pr_url: "https://github.com/user/repo/pull/123"
  - status: "in_review"
  ↓
code review agent triggered:
  - fetches PR diff
  - reviews code changes
  - checks for common issues
  - runs static analysis
  - checks test coverage
  ↓
stores result in beadster_agent_results
  ↓
adds comment to issue with review
  ↓
if approved:
  - status: "approved"
else:
  - status: "needs_work"
  - creates follow-up issues for each problem
```

## mcp tools

```typescript
// dependency management
tools: [
  'dep_add',       // add dependency
  'dep_remove',    // remove dependency
  'dep_list',      // list dependencies
  'dep_tree',      // show dependency tree

  // ready work
  'ready_list',    // list ready issues (no blockers)
  'blocked_list',  // list blocked issues

  // agent management
  'agent_trigger', // manually trigger agent
  'agent_status',  // check agent execution status
  'agent_results', // get agent results for issue
]
```

## api endpoints

```typescript
// dependencies
POST /api/issues/:id/dependencies
GET /api/issues/:id/dependencies
DELETE /api/issues/:id/dependencies/:depends_on_id

// ready work
GET /api/issues/ready
GET /api/issues/blocked

// agents
POST /api/agents/:type/trigger
GET /api/agents/executions/:id
GET /api/issues/:id/agent-results
```

## ui views

### dependency graph

```
beadster.com/issues/bd-10/dependencies

dependency tree for bd-10: auth system (epic)

→ bd-10: auth system [epic]
  ├─ bd-11: user registration [task] (completed)
  ├─ bd-12: user login [task] (in progress)
  └─ bd-13: password reset [task] (blocked by bd-14)
      └─ bd-14: email service setup [task] (open)
```

### ready work view

```
beadster.com/ready

ready work (5 issues)

filter by: [priority ▼] [labels ▼] [source ▼]

1. [P0] bd-1: fix critical auth bug (no blockers)
2. [P1] bd-14: email service setup (no blockers)
3. [P1] bd-8: add oauth providers (no blockers)
4. [P2] bd-20: improve error messages (no blockers)
5. [P2] bd-25: update docs (no blockers)
```

### discovered work view

```
beadster.com/issues/bd-5/discovered

work discovered from bd-5: implement api

bd-15: add rate limiting (open)
bd-16: add request validation (open)
bd-17: improve error handling (completed)

total: 3 issues discovered
```

## benefits

combining dependencies + agents:

1. **smart prioritization**: agents work on ready issues only
2. **automatic discovery**: agents file issues for todos/bugs they find
3. **provenance tracking**: know why each issue exists
4. **dependency awareness**: agents respect blockers
5. **parallel work**: related issues can be worked simultaneously
6. **hierarchy**: epics organize large features
7. **audit trail**: see what agents did and why
