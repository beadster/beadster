# beadster database schema

complete d1/sqlite schema for beadster cloud

## core tables

### users

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE,
  name TEXT,
  apple_id TEXT UNIQUE,
  api_key TEXT UNIQUE,
  created_at INTEGER,
  updated_at INTEGER
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_api_key ON users(api_key);
```

### devices

```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  hardware_uuid TEXT UNIQUE,
  device_name TEXT,
  device_type TEXT,  -- 'mac', 'iphone', 'ipad', 'linux', 'windows'
  platform TEXT,
  platform_version TEXT,
  first_seen INTEGER,
  last_seen INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_hardware ON devices(hardware_uuid);
```

### sources

```sql
CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT,
  type TEXT,  -- 'local-git', 'local-no-git', 'virtual', 'inbox'
  path TEXT,
  machine_id TEXT,
  last_sync INTEGER,
  cloud_only BOOLEAN DEFAULT 0,
  first_seen INTEGER,
  issue_count INTEGER DEFAULT 0,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_sources_user ON sources(user_id);
CREATE INDEX idx_sources_type ON sources(type);
```

### issues

```sql
CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  beads_id TEXT,  -- local bd id like "bd-123"

  -- core fields
  title TEXT NOT NULL,
  body TEXT,
  status TEXT DEFAULT 'open',  -- 'open', 'in_progress', 'blocked', 'closed'
  priority INTEGER DEFAULT 2,  -- 0-4 (0=highest)
  issue_type TEXT DEFAULT 'task',  -- 'bug', 'feature', 'task', 'epic', 'chore'

  -- assignment
  assignee TEXT,

  -- detailed planning
  design TEXT,  -- solution design
  acceptance_criteria TEXT,  -- definition of done
  notes TEXT,  -- working notes
  estimated_minutes INTEGER,

  -- labels (stored as JSON array)
  labels TEXT,  -- ["urgent", "backend", "api"]

  -- git integration
  git_repo TEXT,
  git_branch TEXT,
  git_commit TEXT,  -- commit SHA when closed
  git_pr_url TEXT,
  git_pr_number TEXT,

  -- triage (for customer bugs)
  triage_status TEXT,  -- 'new', 'triaged', 'accepted', 'rejected'
  triaged_at INTEGER,
  triaged_by_user_id TEXT,
  triage_notes TEXT,

  -- reporter tracking
  reporter_type TEXT,  -- 'internal', 'customer', 'agent', 'integration'
  reporter_id TEXT,
  reporter_email TEXT,
  reporter_name TEXT,

  -- urgency/impact (for customer bugs)
  urgency TEXT,  -- 'low', 'medium', 'high', 'critical'
  impact TEXT,  -- 'low', 'medium', 'high'

  -- backlog management
  backlog_status TEXT,  -- 'inbox', 'backlog', 'active', 'archive'
  backlog_priority INTEGER,
  accepted_at INTEGER,
  started_at INTEGER,

  -- session tracking (which claude session created it)
  session_id TEXT,
  client TEXT,  -- 'claude-code', 'claude-desktop', 'web', 'ios-app'

  -- device tracking
  created_by_user_id TEXT,
  created_by_device_id TEXT,
  created_by_client TEXT,
  updated_by_user_id TEXT,
  updated_by_device_id TEXT,
  updated_by_client TEXT,

  -- timestamps
  synced_at INTEGER,
  created_at INTEGER,
  updated_at INTEGER,
  closed_at INTEGER,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (triaged_by_user_id) REFERENCES users(id),
  FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  FOREIGN KEY (created_by_device_id) REFERENCES devices(id),
  FOREIGN KEY (updated_by_user_id) REFERENCES users(id),
  FOREIGN KEY (updated_by_device_id) REFERENCES devices(id)
);

CREATE INDEX idx_issues_user ON issues(user_id);
CREATE INDEX idx_issues_source ON issues(source_id);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_priority ON issues(priority);
CREATE INDEX idx_issues_session ON issues(session_id);
CREATE INDEX idx_issues_triage ON issues(triage_status);
CREATE INDEX idx_issues_backlog ON issues(backlog_status);
```

### dependencies

four types following beads pattern:

```sql
CREATE TABLE dependencies (
  issue_id TEXT NOT NULL,
  depends_on_id TEXT NOT NULL,
  type TEXT NOT NULL,  -- 'blocks', 'related', 'parent-child', 'discovered-from'
  created_at INTEGER,
  created_by_user_id TEXT,
  created_by_device_id TEXT,
  PRIMARY KEY (issue_id, depends_on_id, type),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (depends_on_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  FOREIGN KEY (created_by_device_id) REFERENCES devices(id)
);

CREATE INDEX idx_deps_issue ON dependencies(issue_id);
CREATE INDEX idx_deps_depends ON dependencies(depends_on_id);
CREATE INDEX idx_deps_type ON dependencies(type);
CREATE INDEX idx_deps_blocks ON dependencies(issue_id) WHERE type = 'blocks';
```

dependency types:
- `blocks`: hard dependency, affects ready work queue
- `related`: soft relationship, doesn't block
- `parent-child`: epic/subtask hierarchy
- `discovered-from`: provenance, tracks work discovered during other work

### events

complete audit trail:

```sql
CREATE TABLE events (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  event_type TEXT NOT NULL,  -- 'created', 'updated', 'commented', 'closed', 'dependency_added', 'status_changed'
  actor_user_id TEXT,
  actor_device_id TEXT,
  actor_client TEXT,
  old_value TEXT,  -- JSON before change
  new_value TEXT,  -- JSON after change
  comment TEXT,  -- for comments and close reasons
  created_at INTEGER,
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (actor_user_id) REFERENCES users(id),
  FOREIGN KEY (actor_device_id) REFERENCES devices(id)
);

CREATE INDEX idx_events_issue ON events(issue_id);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_created ON events(created_at);
```

### sessions

track claude sessions:

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT,
  client TEXT,  -- 'claude-code', 'claude-desktop', 'web', 'ios-app'
  device_id TEXT,
  project_name TEXT,
  first_issue_at INTEGER,
  last_issue_at INTEGER,
  issue_count INTEGER DEFAULT 0,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_source ON sessions(source_id);
CREATE INDEX idx_sessions_device ON sessions(device_id);
```

## views

### ready_issues

issues with no open blockers (like beads):

```sql
CREATE VIEW ready_issues AS
SELECT i.*
FROM issues i
WHERE i.status = 'open'
  AND NOT EXISTS (
    SELECT 1 FROM dependencies d
    JOIN issues blocker ON d.depends_on_id = blocker.id
    WHERE d.issue_id = i.id
      AND d.type = 'blocks'
      AND blocker.status IN ('open', 'in_progress', 'blocked')
  );
```

### blocked_issues

issues with open blockers:

```sql
CREATE VIEW blocked_issues AS
SELECT
  i.*,
  COUNT(d.depends_on_id) as blocked_by_count,
  GROUP_CONCAT(d.depends_on_id) as blocked_by_ids
FROM issues i
JOIN dependencies d ON i.id = d.issue_id
JOIN issues blocker ON d.depends_on_id = blocker.id
WHERE i.status IN ('open', 'in_progress', 'blocked')
  AND d.type = 'blocks'
  AND blocker.status IN ('open', 'in_progress', 'blocked')
GROUP BY i.id;
```

## extension tables

following beads pattern, users can add custom tables with `beadster_` prefix

### example: agent executions

```sql
CREATE TABLE beadster_executions (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  agent_type TEXT NOT NULL,  -- 'triage', 'research', 'qa'
  status TEXT NOT NULL,  -- 'pending', 'running', 'completed', 'failed'
  agent_name TEXT,
  started_at INTEGER,
  completed_at INTEGER,
  error TEXT,
  actions_taken TEXT,  -- JSON log
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_executions_issue ON beadster_executions(issue_id);
CREATE INDEX idx_executions_status ON beadster_executions(status);
```

### example: agent results

generic storage for any agent output:

```sql
CREATE TABLE beadster_agent_results (
  id TEXT PRIMARY KEY,
  execution_id TEXT NOT NULL,
  result_type TEXT NOT NULL,  -- 'research', 'code_review', 'qa_test', 'triage', etc
  result_data TEXT NOT NULL,  -- JSON with agent-specific output
  created_at INTEGER,
  FOREIGN KEY (execution_id) REFERENCES beadster_executions(id) ON DELETE CASCADE
);

CREATE INDEX idx_agent_results_execution ON beadster_agent_results(execution_id);
CREATE INDEX idx_agent_results_type ON beadster_agent_results(result_type);
```

example result_data for different agents:

```json
// research agent
{
  "research_type": "technical",
  "questions": ["how does X compare to Y?"],
  "findings": "## Summary\n...",
  "sources": ["https://...", "https://..."]
}

// code review agent
{
  "files_reviewed": 5,
  "issues_found": ["missing error handling", "unused variable"],
  "suggestions": ["add try-catch", "remove unused import"]
}

// qa agent
{
  "tests_run": 42,
  "tests_passed": 40,
  "tests_failed": 2,
  "failure_details": [...]
}
```

### example: checkpoints

```sql
CREATE TABLE beadster_checkpoints (
  id TEXT PRIMARY KEY,
  execution_id TEXT NOT NULL,
  phase TEXT NOT NULL,
  checkpoint_data TEXT,  -- JSON
  created_at INTEGER,
  FOREIGN KEY (execution_id) REFERENCES beadster_executions(id) ON DELETE CASCADE
);

CREATE INDEX idx_checkpoints_execution ON beadster_checkpoints(execution_id);
```

## customer support tables

### customers

```sql
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,  -- which beadster user owns this customer
  email TEXT,
  name TEXT,
  company TEXT,
  external_id TEXT,  -- id from intercom/zendesk/etc
  created_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_customers_user ON customers(user_id);
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_external ON customers(external_id);
```

## query examples

### get ready work for user

```sql
SELECT * FROM ready_issues
WHERE user_id = ?
ORDER BY priority ASC, created_at ASC
LIMIT 10;
```

### get issues blocked by specific issue

```sql
SELECT i.*
FROM issues i
JOIN dependencies d ON d.issue_id = i.id
WHERE d.depends_on_id = ?
  AND d.type = 'blocks';
```

### get dependency tree

```sql
WITH RECURSIVE deps(id, level) AS (
  SELECT id, 0 FROM issues WHERE id = ?
  UNION ALL
  SELECT d.depends_on_id, deps.level + 1
  FROM dependencies d
  JOIN deps ON d.issue_id = deps.id
  WHERE d.type IN ('blocks', 'parent-child')
)
SELECT i.*, deps.level
FROM deps
JOIN issues i ON i.id = deps.id
ORDER BY deps.level, i.priority;
```

### get issues by session

```sql
SELECT * FROM issues
WHERE session_id = ?
ORDER BY created_at ASC;
```

### get untriaged customer bugs

```sql
SELECT * FROM issues
WHERE reporter_type = 'customer'
  AND triage_status = 'new'
ORDER BY created_at ASC;
```

### get issues discovered from specific issue

```sql
SELECT i.*
FROM issues i
JOIN dependencies d ON d.issue_id = i.id
WHERE d.depends_on_id = ?
  AND d.type = 'discovered-from'
ORDER BY i.created_at DESC;
```

### get user's device activity

```sql
SELECT
  d.device_name,
  d.device_type,
  COUNT(i.id) as issues_created,
  MAX(i.created_at) as last_issue
FROM devices d
LEFT JOIN issues i ON i.created_by_device_id = d.id
WHERE d.user_id = ?
GROUP BY d.id
ORDER BY last_issue DESC;
```

## migration notes

when adding fields to existing schema:
- use ALTER TABLE for backward compatibility
- set reasonable defaults
- update sync daemon to handle new fields
- update mcp tools to expose new fields

example migration:

```sql
-- add git integration fields
ALTER TABLE issues ADD COLUMN git_repo TEXT;
ALTER TABLE issues ADD COLUMN git_branch TEXT;
ALTER TABLE issues ADD COLUMN git_commit TEXT;

-- add triage fields
ALTER TABLE issues ADD COLUMN triage_status TEXT DEFAULT 'new';
ALTER TABLE issues ADD COLUMN urgency TEXT DEFAULT 'medium';
```

## performance considerations

d1 limits:
- 10MB database size per database
- can shard by user_id if needed

indexes:
- already created for common queries
- add custom indexes for specific use cases
- composite indexes for complex filters

json fields:
- use for flexible data (labels, checkpoint_data)
- d1 supports json functions: json_extract, json_array_length

batching:
- use transactions for multi-row inserts
- batch sync operations to reduce api calls
