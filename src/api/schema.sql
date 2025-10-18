-- Beadster Database Schema

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE,
  api_key TEXT UNIQUE NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_api_key ON users(api_key);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,  -- 'local', 'virtual', 'inbox'
  path TEXT,
  last_sync INTEGER,
  last_issue_number INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_sources_user ON sources(user_id);

CREATE TABLE issues (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT NOT NULL,

  -- From Beads
  beads_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  status TEXT NOT NULL,
  priority TEXT,
  labels TEXT,  -- JSON array

  -- Session tracking (extracted from labels)
  session_id TEXT,
  client TEXT,  -- 'claude-code', 'claude-desktop', etc
  project_name TEXT,

  -- Sync
  synced_at INTEGER,

  -- Timestamps
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  closed_at INTEGER,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id)
);

CREATE INDEX idx_issues_user ON issues(user_id);
CREATE INDEX idx_issues_source ON issues(source_id);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_session ON issues(session_id);
CREATE INDEX idx_issues_client ON issues(client);

-- Ensure beads_id is unique per source
CREATE UNIQUE INDEX idx_issues_source_beads_id ON issues(source_id, beads_id);

-- Sessions for grouping
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_id TEXT,
  client TEXT NOT NULL,
  project_name TEXT,
  first_issue_at INTEGER,
  last_issue_at INTEGER,
  issue_count INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (source_id) REFERENCES sources(id)
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_source ON sessions(source_id);
CREATE INDEX idx_sessions_last_issue ON sessions(last_issue_at);

-- Devices for tracking which machine/client
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  hardware_uuid TEXT UNIQUE,
  device_name TEXT,
  device_type TEXT,  -- 'mac', 'iphone', 'ipad', 'linux', 'windows', 'web'
  platform TEXT,
  platform_version TEXT,
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_hardware ON devices(hardware_uuid);

-- Track which devices have seen which issues (for consensus & safe ID renumbering)
CREATE TABLE device_issue_tracking (
  issue_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  client TEXT NOT NULL,  -- 'macos', 'ios', 'web', 'cli', 'github-client'
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (issue_id, device_id),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX idx_device_issue_tracking_issue ON device_issue_tracking(issue_id);
CREATE INDEX idx_device_issue_tracking_device ON device_issue_tracking(device_id);
CREATE INDEX idx_device_issue_tracking_client ON device_issue_tracking(client);

-- Track next beads_id sequence per source (prevents web/mobile ID collisions)
CREATE TABLE source_sequences (
  source_id TEXT PRIMARY KEY,
  next_beads_id INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE
);

CREATE INDEX idx_source_sequences_source ON source_sequences(source_id);
