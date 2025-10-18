# linked docs feature

track which documentation is associated with which issues

## concept

when creating issues from a specific document or design, link the issue back to that document for context

## use cases

**planning from architecture docs:**
- read docs/SYNC_AND_CONFLICTS.md
- create 5 implementation tasks
- each task links back to relevant section
- developers can find design context easily

**feature specs:**
- docs/FEATURES/FEATURE_GIT_INFO.md describes feature
- create tasks for implementation
- tasks reference the spec doc
- changes to spec can notify linked issues

**investigation results:**
- research agent creates docs/RESEARCH/auth_options.md
- creates tasks based on research
- tasks link to research doc
- context preserved for implementation

## schema

### option 1: add field to issues table

```sql
ALTER TABLE issues ADD COLUMN linked_doc TEXT;  -- path to doc like "docs/SYNC_AND_CONFLICTS.md"
```

simple but limited - only one doc per issue

### option 2: separate table (flexible)

```sql
CREATE TABLE issue_docs (
  issue_id TEXT NOT NULL,
  doc_path TEXT NOT NULL,
  doc_section TEXT,           -- optional: "## device_issue_tracking table"
  link_type TEXT NOT NULL,    -- 'implements', 'references', 'based-on', 'generated-from'
  created_at INTEGER,
  PRIMARY KEY (issue_id, doc_path),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_issue_docs_issue ON issue_docs(issue_id);
CREATE INDEX idx_issue_docs_path ON issue_docs(doc_path);
```

supports multiple docs per issue and multiple issues per doc

### option 3: simple text reference (lightweight)

just mention doc in description with convention:

```markdown
Implement device_issue_tracking table.

See: docs/SYNC_AND_CONFLICTS.md#device_issue_tracking-table-visibility-tracking
```

no schema changes, searchable with grep

## link types

**implements:**
- issue implements what the doc describes
- doc is design/spec, issue is implementation
- example: "implement X feature" → "docs/FEATURES/FEATURE_X.md"

**references:**
- issue mentions doc for context
- doc provides background info
- example: "fix auth bug" → "docs/AUTH_ARCHITECTURE.md"

**based-on:**
- issue created based on doc recommendations
- doc is research/analysis, issue is decision
- example: "use postgres" → "docs/RESEARCH/database_comparison.md"

**generated-from:**
- issue auto-created from doc parsing
- doc is source of work items
- example: tasks from "docs/TODO.md"

## implementation (extending bd)

beads only supports extending the database, not the CLI. so we use custom tables:

```sql
-- beadster adds this table to .beads/*.db
CREATE TABLE IF NOT EXISTS beadster_issue_docs (
  issue_id TEXT NOT NULL,
  doc_path TEXT NOT NULL,
  doc_section TEXT,
  link_type TEXT NOT NULL,
  created_at INTEGER,
  PRIMARY KEY (issue_id, doc_path),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_beadster_issue_docs_issue ON beadster_issue_docs(issue_id);
CREATE INDEX idx_beadster_issue_docs_path ON beadster_issue_docs(doc_path);
```

then beadster provides its own tools (not bd):

```bash
# beadster cli (separate from bd)
beadster link-doc bd-46 docs/SYNC_AND_CONFLICTS.md --section "device_issue_tracking"

# or via mcp
mcp link_doc --issue bd-46 --doc docs/SYNC_AND_CONFLICTS.md

# query linked docs
sqlite3 .beads/myapp.db "
  SELECT i.id, i.title, d.doc_path, d.doc_section
  FROM issues i
  JOIN beadster_issue_docs d ON i.id = d.issue_id
  WHERE d.doc_path = 'docs/SYNC_AND_CONFLICTS.md'
"
```

use bd as-is, beadster extends the database

## agent workflow

```typescript
// agent reads doc and creates tasks
const doc = await readFile('docs/SYNC_AND_CONFLICTS.md');
const sections = parseMarkdownSections(doc);

for (const section of sections) {
  if (section.isImplementable) {
    await bd.create({
      title: `implement ${section.title}`,
      description: section.content,
      linked_doc: 'docs/SYNC_AND_CONFLICTS.md',
      doc_section: section.heading,
      link_type: 'implements'
    });
  }
}

// later: find all issues for this doc
const issues = await bd.list({
  linked_doc: 'docs/SYNC_AND_CONFLICTS.md'
});
```

## web ui

```astro
---
// pages/docs/[...path].astro
const docPath = Astro.params.path;
const linkedIssues = await getIssuesForDoc(docPath);
---

<div class="doc-view">
  <div class="doc-content">
    <!-- rendered markdown -->
  </div>

  <aside class="linked-issues">
    <h3>related issues ({linkedIssues.length})</h3>
    {linkedIssues.map(issue => (
      <div class="issue">
        <a href={`/issues/${issue.id}`}>
          {issue.beads_id}: {issue.title}
        </a>
        <span class="link-type">{issue.link_type}</span>
      </div>
    ))}
  </aside>
</div>
```

## bidirectional navigation

**from issue → doc:**
```
beadster-46: implement device_issue_tracking table

linked docs:
- docs/SYNC_AND_CONFLICTS.md (implements)
  section: device_issue_tracking table (visibility tracking)
```

**from doc → issues:**
```
docs/SYNC_AND_CONFLICTS.md

implemented by:
- beadster-46: implement device_issue_tracking table
- beadster-47: implement source_sequences table
- beadster-48: implement basic sync daemon

referenced by:
- beadster-35: explore issue visibility tracking
```

## git integration

track when doc changes after issues created:

```sql
ALTER TABLE issue_docs ADD COLUMN doc_hash TEXT;  -- git hash when linked
```

```bash
# detect stale links
for issue_doc in issue_docs:
  current_hash = git rev-parse HEAD:${doc_path}
  if current_hash != issue_doc.doc_hash:
    notify "doc ${doc_path} changed since beadster-${issue_id} was created"
```

## beadster mcp tools

beadster mcp server (not bd) provides:

```typescript
tools: [
  'beadster_link_doc',      // link doc to issue
  'beadster_unlink_doc',    // remove doc link
  'beadster_list_doc_issues', // get issues for doc
  'beadster_update_doc_hash'  // refresh git hash after doc update
]

// usage
await mcp.beadster_link_doc({
  issue_id: 'bd-46',
  doc_path: 'docs/SYNC_AND_CONFLICTS.md',
  doc_section: 'device_issue_tracking table',
  link_type: 'implements'
});
```

## example session

```
User: read docs/SYNC_AND_CONFLICTS.md and create implementation tasks

Agent: [reads doc]
Agent: I'll create tasks for the main implementation sections:

# use bd to create issues
bd create "implement source_sequences table" \
  -d "See docs/SYNC_AND_CONFLICTS.md web/mobile issue creation section" \
  -p 1 -t task

# then link via beadster
beadster link-doc bd-46 docs/SYNC_AND_CONFLICTS.md \
  --section "web/mobile issue creation" \
  --type implements

bd create "implement device_issue_tracking table" \
  -d "See docs/SYNC_AND_CONFLICTS.md device_issue_tracking section" \
  -p 1 -t task

beadster link-doc bd-47 docs/SYNC_AND_CONFLICTS.md \
  --section "device_issue_tracking table" \
  --type implements

All tasks linked to docs/SYNC_AND_CONFLICTS.md for easy reference.

User: show me issues for that doc

Agent: beadster list-doc-issues docs/SYNC_AND_CONFLICTS.md

beadster-46: implement source_sequences table (P1, open)
  section: web/mobile issue creation
beadster-47: implement device_issue_tracking table (P1, open)
  section: device_issue_tracking table
```

## benefits

**for developers:**
- quick access to design context
- understand why feature was built this way
- find related work easily

**for agents:**
- maintain context across sessions
- link research to implementation
- track spec changes

**for teams:**
- see implementation status of design docs
- know which docs are actively being worked on
- understand impact of doc changes

## recommendation

**immediately: option 3 (text reference)** - works with bd today:
```bash
bd create "implement sync" \
  -d "See docs/SYNC_AND_CONFLICTS.md for design"
```
- include doc path in issue description
- use markdown links with sections
- searchable with bd and grep

**later: option 2 (custom table)** - extend bd database:
```sql
CREATE TABLE beadster_issue_docs (...);
```
- beadster adds table to .beads/*.db
- beadster CLI/MCP manages links
- bd continues to work as-is
- query across both with SQL joins

**never: option 1 (modify bd)** - not supported:
- cannot add `--doc` flag to bd CLI
- cannot modify bd schema
- bd is maintained by beads project
