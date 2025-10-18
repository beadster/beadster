-- Add missing tables to remote database

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
