# Scaling beadster for Teams

## Beads TEXT_FORMATS.md Recommendations

From the Beads documentation:

**Team size guidelines:**
- **1-5 developers:** Binary format fine, git handles merges
- **5-20 developers:** Text format (JSONL) recommended for better diffs
- **20+ developers:** Shared server required

**Conflict rates:**
- Append-only workflows: 5% false conflicts
- Update-heavy workflows: 50% real conflicts

**Key insight:** At scale, git merge conflicts become the bottleneck.

## beadster Solves This

beadster is already designed as the "shared server" for teams!

### Architecture for Teams

```
Team Member 1 (Mac)
  ├── Local .beads/ (git-backed)
  └── Sync daemon → beadster Cloud

Team Member 2 (Mac)
  ├── Local .beads/ (git-backed)
  └── Sync daemon → beadster Cloud

Team Member 3 (iOS)
  └── beadster app → Cloud (no local .beads/)

beadster Cloud (Shared Server)
  └── Cloudflare D1 (SQLite) or PostgreSQL
```

**Result:**
- No more git merge conflicts on issues
- Real-time sync via cloud
- Each developer can still use local .beads/ + bd CLI
- But sync happens through beadster, not git push/pull

## Database Backend Options

### Option 1: Cloudflare D1 (SQLite)

**Current architecture plan**

**Pros:**
- ✅ Serverless, scales automatically
- ✅ Simple setup
- ✅ Very fast reads
- ✅ Perfect for < 1000 users
- ✅ Free tier: 5GB storage, 5M reads/day
- ✅ Edge deployment (low latency worldwide)

**Cons:**
- ❌ Single-writer (writes go to primary region)
- ❌ 10MB database size limit (per database, but can shard)
- ❌ Not ideal for 1000+ concurrent writers

**When to use:**
- Small to medium teams (< 100 people)
- Moderate write load
- Want serverless simplicity

### Option 2: PostgreSQL (Neon/Supabase/RDS)

**For larger teams**

**Pros:**
- ✅ Multi-writer, true concurrent writes
- ✅ Battle-tested at scale
- ✅ Advanced features (full-text search, JSON operators)
- ✅ Can handle 1000+ users
- ✅ Larger storage capacity

**Cons:**
- ❌ More complex setup
- ❌ Higher cost
- ❌ Need to manage connections/pooling

**When to use:**
- Large teams (100+ people)
- High write concurrency
- Need advanced SQL features

### Option 3: Hybrid

**Best of both worlds**

```
beadster uses D1 by default
↓
Team grows beyond D1 limits
↓
Migrate to PostgreSQL
```

**Implementation:**

```typescript
// Abstract database interface
interface beadsterDatabase {
  getIssues(userId: string, filters: Filters): Promise<Issue[]>;
  createIssue(issue: Issue): Promise<void>;
  updateIssue(id: string, updates: Partial<Issue>): Promise<void>;
  // ... etc
}

// D1 implementation
class D1Database implements beadsterDatabase {
  constructor(private db: D1Database) {}

  async getIssues(userId: string, filters: Filters) {
    return await this.db.prepare(`
      SELECT * FROM issues WHERE user_id = ?
    `).bind(userId).all();
  }

  // ... etc
}

// PostgreSQL implementation
class PostgresDatabase implements beadsterDatabase {
  constructor(private pool: Pool) {}

  async getIssues(userId: string, filters: Filters) {
    const result = await this.pool.query(
      'SELECT * FROM issues WHERE user_id = $1',
      [userId]
    );
    return result.rows;
  }

  // ... etc
}

// Factory
function createDatabase(env: Env): beadsterDatabase {
  if (env.POSTGRES_URL) {
    return new PostgresDatabase(createPool(env.POSTGRES_URL));
  }
  return new D1Database(env.DB);
}
```

## Scaling Considerations

### 1. Per-User Issue Count

**Typical scenario:**
- User has 30 coding projects
- Each project averages 50 issues
- Total: 1,500 issues per user

**At 1000 users:**
- 1.5 million issues total
- D1: Can handle this easily
- PostgreSQL: Overkill but faster queries

**At 10,000 users:**
- 15 million issues
- D1: Approaching limits, shard by user
- PostgreSQL: Recommended

### 2. Write Patterns

**Solo developers:**
- Mostly appends (new issues)
- Few updates
- Low concurrency
- D1 perfect

**Teams (5-20 people):**
- More updates (status changes)
- Moderate concurrency
- Multiple people updating same source
- D1 still fine with optimistic locking

**Large teams (20+ people):**
- Heavy updates
- High concurrency
- Real-time collaboration
- PostgreSQL recommended

### 3. Query Complexity

**Simple queries (D1 fine):**
```sql
SELECT * FROM issues WHERE user_id = ? AND status = 'open'
```

**Complex queries (PostgreSQL better):**
```sql
SELECT
  i.*,
  COUNT(DISTINCT d.blocked_by_id) as blocker_count,
  json_agg(DISTINCT l.label) as labels
FROM issues i
LEFT JOIN dependencies d ON d.issue_id = i.id
LEFT JOIN issue_labels l ON l.issue_id = i.id
WHERE i.user_id = ?
  AND i.status = 'open'
  AND (
    i.labels @> '["urgent"]'::jsonb OR
    i.priority = 'high'
  )
GROUP BY i.id
HAVING COUNT(DISTINCT d.blocked_by_id) = 0
ORDER BY i.created_at DESC
```

## Team Features

### Real-Time Collaboration

**With PostgreSQL:**

```typescript
// Use PostgreSQL LISTEN/NOTIFY
app.get('/api/issues/stream', async (c) => {
  const user = await authenticate(c);

  // Server-Sent Events
  return c.stream(async (stream) => {
    const client = await pool.connect();

    // Listen for changes
    await client.query(`LISTEN issue_changes`);

    client.on('notification', (msg) => {
      const change = JSON.parse(msg.payload);

      // Only send if relevant to this user
      if (change.user_id === user.id) {
        stream.write(`data: ${JSON.stringify(change)}\n\n`);
      }
    });

    // When issue updated, trigger notification
    await client.query(`NOTIFY issue_changes, '${JSON.stringify(change)}'`);
  });
});
```

**With D1:**

```typescript
// Poll-based approach
app.get('/api/issues/changes', async (c) => {
  const user = await authenticate(c);
  const { since } = c.req.query();

  const changes = await env.DB.prepare(`
    SELECT * FROM issues
    WHERE user_id = ? AND updated_at > ?
  `).bind(user.id, since).all();

  return c.json(changes);
});

// Client polls every 5 seconds
setInterval(async () => {
  const changes = await fetch('/api/issues/changes?since=' + lastSync);
  // Update UI
}, 5000);
```

### Team Presence

**Who's working on what:**

```sql
CREATE TABLE team_presence (
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  issue_id TEXT,
  last_seen INTEGER,
  status TEXT,  -- 'active', 'idle'
  PRIMARY KEY (user_id, source_id)
);

CREATE INDEX idx_team_presence_source ON team_presence(source_id);
```

```typescript
// Update presence
app.post('/api/presence', async (c) => {
  const user = await authenticate(c);
  const { source_id, issue_id, status } = await c.req.json();

  await env.DB.prepare(`
    INSERT INTO team_presence (user_id, source_id, issue_id, last_seen, status)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(user_id, source_id) DO UPDATE SET
      issue_id = excluded.issue_id,
      last_seen = excluded.last_seen,
      status = excluded.status
  `).run(user.id, source_id, issue_id, Date.now(), status);

  return c.json({ ok: true });
});

// Get team presence for source
app.get('/api/sources/:id/presence', async (c) => {
  const sourceId = c.req.param('id');

  const presence = await env.DB.prepare(`
    SELECT
      p.*,
      u.name,
      u.email,
      i.title as issue_title
    FROM team_presence p
    JOIN users u ON u.id = p.user_id
    LEFT JOIN issues i ON i.id = p.issue_id
    WHERE p.source_id = ?
      AND p.last_seen > ?
      AND p.status = 'active'
  `).bind(sourceId, Date.now() - 5 * 60 * 1000).all(); // Active in last 5 min

  return c.json(presence);
});
```

### Activity Feed

**Team activity log:**

```sql
CREATE TABLE activity_feed (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  issue_id TEXT,
  activity_type TEXT NOT NULL,  -- 'created', 'updated', 'closed', 'commented'
  activity_data TEXT,  -- JSON
  created_at INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (issue_id) REFERENCES issues(id)
);

CREATE INDEX idx_activity_feed_source ON activity_feed(source_id, created_at DESC);
CREATE INDEX idx_activity_feed_user ON activity_feed(user_id, created_at DESC);
```

**UI shows team activity:**

```
Team Activity - main-app

John Doe closed issue #54 "Fix login bug"
  2 minutes ago

Jane Smith created issue #55 "Add OAuth"
  10 minutes ago

John Doe updated issue #53 "Update docs"
  Status: in progress → done
  15 minutes ago
```

## Migration Path

### Phase 1: Launch (D1)

```
beadster.com launches
- Cloudflare Workers + D1
- Serverless, simple
- Free tier covers early users
```

### Phase 2: Growth (D1 + Optimization)

```
500 users
- Still on D1
- Add caching (KV)
- Optimize queries
- Monitor limits
```

### Phase 3: Scale (PostgreSQL)

```
5,000+ users or hitting D1 limits
- Migrate to PostgreSQL (Neon/Supabase)
- Keep same API
- Just swap database backend
- Add connection pooling
```

**Migration script:**

```typescript
// Migrate from D1 to PostgreSQL
async function migrate() {
  const d1 = new D1Database(env.DB);
  const pg = new PostgresDatabase(pool);

  // Export all data from D1
  console.log('Exporting from D1...');
  const users = await d1.getAllUsers();
  const sources = await d1.getAllSources();
  const issues = await d1.getAllIssues();

  // Import to PostgreSQL
  console.log('Importing to PostgreSQL...');
  for (const user of users) {
    await pg.createUser(user);
  }
  for (const source of sources) {
    await pg.createSource(source);
  }
  for (const issue of issues) {
    await pg.createIssue(issue);
  }

  console.log('Migration complete!');
}
```

## Cost Comparison

### D1 (Cloudflare)

**Free tier:**
- 5GB storage
- 5M reads/day
- 100K writes/day

**Paid:**
- $0.75 per million reads
- $1.00 per million writes
- $0.75/GB-month storage

**Estimated cost for 1000 users:**
- ~$50-100/month

### PostgreSQL (Neon)

**Free tier:**
- 512MB storage
- Shared compute

**Pro:**
- $19/month base
- $0.16/GB-month storage
- Additional compute: $0.10/hour

**Estimated cost for 1000 users:**
- ~$200-500/month

### PostgreSQL (Supabase)

**Free tier:**
- 500MB database
- 2GB bandwidth

**Pro:**
- $25/month
- 8GB database
- 50GB bandwidth

**Estimated cost for 1000 users:**
- ~$300-600/month

## Recommendation

### Start with D1

**Reasons:**
1. Serverless simplicity
2. Free tier covers early users
3. Fast development iteration
4. Edge deployment (low latency)
5. Easy to migrate later

### Migrate to PostgreSQL when:

1. **User count > 5,000**
2. **D1 storage > 5GB**
3. **Write concurrency issues**
4. **Need advanced SQL features**
5. **Team collaboration features needed**

### Or: Offer Both Tiers

```
beadster Pricing:

Free Tier:
- Up to 10 sources
- 1,000 issues
- Solo use
- Powered by D1

Pro Tier ($10/month):
- Unlimited sources
- Unlimited issues
- Team collaboration
- Real-time sync
- Powered by PostgreSQL

Team Tier ($50/month):
- Everything in Pro
- Shared sources
- Activity feed
- Team presence
- Priority support
```

**Users on free tier use D1, paid users use PostgreSQL!**

## Summary

**Beads recommendation:** 20+ developers need shared server

**beadster is that shared server!**

**Database choice:**
- **D1 (SQLite):** Start here, simple, scales to 5K users
- **PostgreSQL:** Migrate later when needed

**Key benefits over git:**
- No merge conflicts on issues
- Real-time sync
- Team collaboration features
- Works with or without local .beads/

**Migration path:**
1. Launch with D1 (free, simple)
2. Optimize and cache
3. Migrate to PostgreSQL when scaling demands it
4. Or offer both as different pricing tiers

**beadster abstracts the backend, so choice is transparent to users!**
