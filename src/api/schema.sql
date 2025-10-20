-- Beadster Database Schema

-- Users table (Better Auth compatible)
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT,
  name TEXT,
  image TEXT,
  email_verified INTEGER DEFAULT 0,

  -- GitHub OAuth fields
  github_id INTEGER UNIQUE,
  github_login TEXT,
  github_name TEXT,
  github_email TEXT,
  github_avatar_url TEXT,

  -- API key for CLI/MCP access
  api_key TEXT UNIQUE NOT NULL,

  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_api_key ON users(api_key);
CREATE INDEX idx_users_github_id ON users(github_id);

-- Better Auth sessions table
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  token TEXT UNIQUE NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);
CREATE INDEX idx_sessions_token ON sessions(token);

-- Better Auth OAuth accounts table
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  access_token TEXT,
  refresh_token TEXT,
  id_token TEXT,
  access_token_expires_at INTEGER,
  refresh_token_expires_at INTEGER,
  scope TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(provider_id, account_id)
);

CREATE INDEX idx_accounts_user ON accounts(user_id);
CREATE INDEX idx_accounts_provider ON accounts(provider_id, account_id);

-- Better Auth verification tokens table
CREATE TABLE verifications (
  id TEXT PRIMARY KEY,
  identifier TEXT NOT NULL,
  value TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_verifications_identifier ON verifications(identifier);
CREATE INDEX idx_verifications_expires ON verifications(expires_at);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,  -- 'local', 'virtual', 'inbox'
  path TEXT,

  -- Git repository info
  git_repo_url TEXT,      -- remote origin URL
  git_current_branch TEXT, -- current branch

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
  priority INTEGER,  -- 0-4 (P0-P4, 0=highest)
  issue_type TEXT,  -- bug, feature, task, epic, chore
  labels TEXT,  -- JSON array

  -- Session tracking (extracted from labels)
  session_id TEXT,
  client TEXT,  -- 'claude-code', 'claude-desktop', etc
  project_name TEXT,

  -- Git context (captured when issue created)
  git_repo_url TEXT,      -- remote origin URL
  git_branch TEXT,        -- branch name when created
  git_commit_hash TEXT,   -- commit hash when created
  git_is_dirty INTEGER DEFAULT 0,  -- had uncommitted changes

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
CREATE INDEX idx_issues_git_repo ON issues(git_repo_url);

-- Ensure beads_id is unique per source
CREATE UNIQUE INDEX idx_issues_source_beads_id ON issues(source_id, beads_id);

-- Issue sessions for grouping (renamed from "sessions" to avoid conflict with better-auth)
CREATE TABLE issue_sessions (
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

CREATE INDEX idx_issue_sessions_user ON issue_sessions(user_id);
CREATE INDEX idx_issue_sessions_source ON issue_sessions(source_id);
CREATE INDEX idx_issue_sessions_last_issue ON issue_sessions(last_issue_at);

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

-- Sync operation logs for auditing and diagnostics
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
