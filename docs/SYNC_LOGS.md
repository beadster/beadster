# sync logs

detailed sync operation auditing for beadster

## overview

track every sync operation (push/pull) with full context:
- what synced (counts, issue IDs, changes)
- success/failure status
- conflicts and errors
- performance metrics
- device and network context

## schema

```sql
CREATE TABLE sync_logs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  device_id TEXT,

  -- operation
  operation TEXT NOT NULL,  -- 'push', 'pull'
  direction TEXT NOT NULL,  -- 'up', 'down'
  client TEXT,              -- 'macos', 'ios', 'cli', 'web', 'mcp'

  -- what synced
  issue_count INTEGER DEFAULT 0,
  issues_created INTEGER DEFAULT 0,
  issues_updated INTEGER DEFAULT 0,
  issues_deleted INTEGER DEFAULT 0,
  issue_ids TEXT,           -- JSON array of issue IDs synced

  -- status
  status TEXT NOT NULL,     -- 'success', 'partial', 'failed'
  error_message TEXT,
  error_code TEXT,

  -- conflicts
  conflicts INTEGER DEFAULT 0,
  conflict_details TEXT,    -- JSON array of conflict info

  -- performance
  duration_ms INTEGER,      -- how long sync took
  bytes_sent INTEGER,
  bytes_received INTEGER,

  -- network context
  ip_address TEXT,
  user_agent TEXT,

  -- timestamps
  started_at INTEGER NOT NULL,
  completed_at INTEGER,
  created_at INTEGER NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_sync_logs_user ON sync_logs(user_id);
CREATE INDEX idx_sync_logs_source ON sync_logs(source_id);
CREATE INDEX idx_sync_logs_device ON sync_logs(device_id);
CREATE INDEX idx_sync_logs_status ON sync_logs(status);
CREATE INDEX idx_sync_logs_operation ON sync_logs(operation);
CREATE INDEX idx_sync_logs_started ON sync_logs(started_at DESC);
```

## use cases

diagnostics:
- why did sync fail?
- which device had the problem?
- what conflicts happened?
- performance issues over time

analytics:
- sync patterns by device/client
- error rates and types
- network performance
- usage patterns (peak times, etc)

debugging:
- reproduce sync issues
- audit trail for data changes
- conflict resolution history

compliance:
- who synced what when
- data access audit
- change tracking

## api changes

push endpoint:
```typescript
// before sync
const syncLogId = ulid();
const startTime = Date.now();

try {
  // ... do sync ...

  // log success
  await db.prepare(`
    INSERT INTO sync_logs (
      id, user_id, source_id, device_id,
      operation, direction, client,
      issue_count, issues_created, issues_updated,
      status, duration_ms, started_at, completed_at, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    syncLogId, user.id, source.id, deviceId,
    'push', 'up', client,
    issues.length, createdCount, updatedCount,
    'success', Date.now() - startTime, startTime, Date.now(), Date.now()
  ).run();
} catch (error) {
  // log failure
  await db.prepare(`
    INSERT INTO sync_logs (
      id, user_id, source_id, device_id,
      operation, direction, client,
      status, error_message, error_code,
      duration_ms, started_at, completed_at, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    syncLogId, user.id, source.id, deviceId,
    'push', 'up', client,
    'failed', error.message, error.code,
    Date.now() - startTime, startTime, Date.now(), Date.now()
  ).run();

  throw error;
}
```

pull endpoint:
```typescript
// similar pattern but direction='down', operation='pull'
```

## new api endpoints

get sync history:
```
GET /api/sync-logs?source_id=xxx&limit=50&status=failed
GET /api/sync-logs/:id
GET /api/devices/:device_id/sync-logs
```

get sync stats:
```
GET /api/sync-stats?source_id=xxx&period=7d
  returns:
  - total syncs
  - success rate
  - avg duration
  - error breakdown
  - peak times
```

## privacy considerations

- ip_address: optional, for security/abuse detection
- user_agent: helps debug client issues
- retention: keep logs for 90 days, then archive or delete
- gdpr: include in user data export/deletion

## performance

- sync_logs can grow large fast
- partition by month if needed
- archive old logs to R2
- use LIMIT on queries
- consider sampling (log every Nth sync or only failures)

## implementation phases

phase 1: basic logging
- track success/failure
- counts only
- no performance metrics yet

phase 2: detailed tracking
- issue IDs
- conflict details
- performance metrics

phase 3: analytics
- stats endpoints
- dashboards
- alerting

## alternatives considered

lightweight approach:
- only log failures (skip successful syncs)
- reduces storage 95%
- still catch all problems
- lose analytics capability

sampled logging:
- log 1% of successful syncs
- log 100% of failures
- balance storage vs insights

combined approach (recommended):
- log all failures (100%)
- log recent successes (7 days)
- sample older successes (1%)
- archive everything to R2 for compliance
