-- Add sync_logs table for sync operation auditing

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
