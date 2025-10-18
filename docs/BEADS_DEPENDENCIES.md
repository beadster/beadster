# beads four dependency types

beadster adopts beads' four dependency dimensions

## the four types

beads defines four distinct relationship types between issues:

### 1. blocks (hard dependency)

**meaning:** issue X must be completed before issue Y can start

**affects ready work:** yes - blocked issues won't show in ready queue

**example:**
```sql
-- bd-2 (implement api) is blocked by bd-1 (design schema)
INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES ('bd-2', 'bd-1', 'blocks');
```

**use cases:**
- "design database schema" blocks "implement api"
- "fix critical bug" blocks "deploy to production"
- "create auth system" blocks "add protected routes"

**behavior:**
- bd-2 won't appear in `ready_issues` view until bd-1 is closed
- explicitly prevents work from starting too early
- enforces proper sequencing

### 2. related (soft relationship)

**meaning:** issues are connected but don't block each other

**affects ready work:** no - both can be worked on independently

**example:**
```sql
-- bd-5 (add dark mode) is related to bd-3 (update theme system)
-- they're connected but can happen in any order
INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES ('bd-5', 'bd-3', 'related');
```

**use cases:**
- "optimize queries" related to "add caching" - both improve performance
- "write docs" related to "implement feature" - can happen in parallel
- "update tests" related to "refactor code" - both part of same area

**behavior:**
- helps organize related work
- shows context when viewing an issue
- doesn't constrain work order

### 3. parent-child (hierarchy)

**meaning:** epic contains subtasks, creates hierarchical grouping

**affects ready work:** no - subtasks are independent

**example:**
```sql
-- create epic
INSERT INTO issues (id, title, issue_type)
VALUES ('bd-10', 'user authentication system', 'epic');

-- create subtasks
INSERT INTO issues (id, title) VALUES
  ('bd-11', 'user registration'),
  ('bd-12', 'user login'),
  ('bd-13', 'password reset');

-- link to epic
INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES
  ('bd-11', 'bd-10', 'parent-child'),
  ('bd-12', 'bd-10', 'parent-child'),
  ('bd-13', 'bd-10', 'parent-child');
```

**use cases:**
- organize large features into smaller tasks
- track epic progress (3/5 subtasks complete)
- filter issues by epic
- plan sprints at epic level

**behavior:**
- subtasks can be worked independently
- closing all children can auto-close epic
- provides drill-down navigation

### 4. discovered-from (provenance)

**meaning:** track issues discovered while working on other issues

**affects ready work:** no - discovery doesn't create blocking

**example:**
```sql
-- while working on bd-5, discovered bd-15
INSERT INTO issues (id, title)
VALUES ('bd-15', 'add rate limiting to api');

INSERT INTO dependencies (issue_id, depends_on_id, type)
VALUES ('bd-15', 'bd-5', 'discovered-from');
```

**use cases:**
- agent finds todos/fixmes in code
- developer discovers bugs during implementation
- spot technical debt during refactoring
- track how backlog grows

**behavior:**
- shows provenance chain
- understand how work spawns more work
- measure productivity (completed 1 issue, discovered 3 more)
- doesn't prevent work on discovered issue

## ready work algorithm

only `blocks` type affects ready work:

```sql
CREATE VIEW ready_issues AS
SELECT i.*
FROM issues i
WHERE i.status = 'open'
  AND NOT EXISTS (
    SELECT 1 FROM dependencies d
    JOIN issues blocker ON d.depends_on_id = blocker.id
    WHERE d.issue_id = i.id
      AND d.type = 'blocks'  -- only this type matters
      AND blocker.status IN ('open', 'in_progress', 'blocked')
  );
```

other types (`related`, `parent-child`, `discovered-from`) don't affect ready status

## comparison table

| type | blocks work | use case | example |
|------|-------------|----------|---------|
| blocks | yes | hard dependency | schema before api |
| related | no | soft relationship | docs with feature |
| parent-child | no | hierarchy | epic with subtasks |
| discovered-from | no | provenance | found while working |

## why four types?

**why not just one "dependency" type?**

different relationships have different semantics:

- `blocks`: sequencing constraint (must do X before Y)
- `related`: organizational (X and Y are about same thing)
- `parent-child`: decomposition (X is part of Y)
- `discovered-from`: history (Y emerged from working on X)

mixing these into one type loses information and makes queries harder

**example scenario:**

```
epic: bd-10 "auth system"
├─ subtask: bd-11 "user registration" (parent-child)
├─ subtask: bd-12 "user login" (parent-child)
│   └─ discovered: bd-15 "add rate limiting" (discovered-from)
│       └─ blocks: bd-2 "implement api" (blocks)
└─ subtask: bd-13 "password reset" (parent-child)
    └─ related: bd-20 "email service" (related)
```

different types capture different semantics clearly

## database schema

```sql
CREATE TABLE dependencies (
  issue_id TEXT NOT NULL,
  depends_on_id TEXT NOT NULL,
  type TEXT NOT NULL,  -- 'blocks', 'related', 'parent-child', 'discovered-from'
  created_at INTEGER,
  created_by_user_id TEXT,
  PRIMARY KEY (issue_id, depends_on_id, type),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (depends_on_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_deps_type ON dependencies(type);
CREATE INDEX idx_deps_blocks ON dependencies(issue_id) WHERE type = 'blocks';
```

note: same two issues can have multiple relationship types simultaneously

## api examples

```typescript
// add blocking dependency
POST /api/issues/bd-2/dependencies
{
  "depends_on_id": "bd-1",
  "type": "blocks"
}

// mark as related
POST /api/issues/bd-5/dependencies
{
  "depends_on_id": "bd-3",
  "type": "related"
}

// link to epic
POST /api/issues/bd-11/dependencies
{
  "depends_on_id": "bd-10",
  "type": "parent-child"
}

// track discovery
POST /api/issues/bd-15/dependencies
{
  "depends_on_id": "bd-5",
  "type": "discovered-from"
}
```

## mcp tools

```typescript
tools: [
  'dep_add',      // add dependency with type
  'dep_remove',   // remove specific dependency
  'dep_list',     // list all dependencies for issue
  'dep_tree',     // show dependency tree
  'ready_list',   // list issues with no blockers
  'blocked_list', // list blocked issues with blocker count
]
```

## ui visualization

### dependency tree

```
bd-10: auth system [epic]
├─ bd-11: user registration [completed]
├─ bd-12: user login [in progress]
│  └─ discovered → bd-15: add rate limiting [open]
│     └─ blocks → bd-2: implement api [blocked]
└─ bd-13: password reset [open]
   └─ related ⟷ bd-20: email service [open]
```

symbols:
- `├─` parent-child
- `└─ discovered →` discovered-from
- `└─ blocks →` blocks
- `⟷` related (bidirectional)

## benefits

adopting beads' four types gives us:

1. **clear semantics** - each type means something specific
2. **smart ready work** - only blocks type prevents work
3. **organizational power** - related and parent-child help organize
4. **provenance tracking** - discovered-from shows how backlog grows
5. **flexible queries** - filter by type for different views
6. **agent-friendly** - agents can reason about different relationships

## beads compatibility

by using exact same types as beads, we can:
- import beads .jsonl files directly
- sync between beads (local) and beadster (cloud)
- use beads cli for local work, beadster for cloud/mobile
- maintain compatibility with beads ecosystem
