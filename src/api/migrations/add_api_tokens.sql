-- API tokens for GitHub Actions and other integrations

CREATE TABLE api_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  token TEXT UNIQUE NOT NULL,  -- format: bst_xxxxxxxx (32 chars)
  scopes TEXT NOT NULL,  -- JSON array: ["sync", "read", "admin"]
  last_used INTEGER,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,  -- NULL = never expires
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_tokens_token ON api_tokens(token);
CREATE INDEX idx_api_tokens_user ON api_tokens(user_id);

-- API token usage tracking for audit logs
CREATE TABLE api_token_usage (
  id TEXT PRIMARY KEY,
  token_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL,
  status INTEGER NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (token_id) REFERENCES api_tokens(id) ON DELETE CASCADE
);

CREATE INDEX idx_api_token_usage_token ON api_token_usage(token_id);
CREATE INDEX idx_api_token_usage_created ON api_token_usage(created_at);

-- Comments:
-- Token scopes:
--   - sync: create and update issues, sources
--   - read: read-only access to issues and sources
--   - admin: full access (delete, manage sources)
-- Token format: bst_ + 32 random base62 characters
-- Example: bst_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
