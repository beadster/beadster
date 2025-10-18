# device tracking

how we track devices in the cloud, same as users

## database schema

```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,              -- device_abc123
  user_id TEXT NOT NULL,

  -- device identity
  hardware_uuid TEXT UNIQUE,        -- IOPlatformUUID on Mac
  device_name TEXT,                 -- "Anton's MacBook Pro"
  device_type TEXT,                 -- "mac", "iphone", "ipad"
  platform TEXT,                    -- "darwin", "ios"
  platform_version TEXT,            -- "14.5"

  -- registration
  first_seen INTEGER,
  last_seen INTEGER,

  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_hardware ON devices(hardware_uuid);
```

## track device in issues

```sql
CREATE TABLE issues (
  -- ... existing fields ...

  -- creation tracking
  created_by_user_id TEXT NOT NULL,
  created_by_device_id TEXT,
  created_by_client TEXT,           -- "claude-code", "web", "ios-app"

  -- update tracking
  updated_by_user_id TEXT,
  updated_by_device_id TEXT,
  updated_by_client TEXT,

  FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  FOREIGN KEY (created_by_device_id) REFERENCES devices(id),
  FOREIGN KEY (updated_by_user_id) REFERENCES users(id),
  FOREIGN KEY (updated_by_device_id) REFERENCES devices(id)
);
```

## sync daemon implementation

```typescript
class SyncDaemon {
  deviceId: string;

  async init() {
    // get or create device ID
    this.deviceId = await this.getOrCreateDeviceId();

    // register device with cloud
    await this.registerDevice();
  }

  async getOrCreateDeviceId(): Promise<string> {
    const configPath = path.join(os.homedir(), '.beadster', 'device.json');

    if (fs.existsSync(configPath)) {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      return config.device_id;
    }

    // generate new device ID from hardware UUID
    const hardwareUuid = await this.getHardwareUuid();
    const deviceId = `device_${this.hashUuid(hardwareUuid)}`;

    // save
    fs.writeFileSync(configPath, JSON.stringify({
      device_id: deviceId,
      hardware_uuid: hardwareUuid,
      created_at: Date.now()
    }));

    return deviceId;
  }

  async getHardwareUuid(): Promise<string> {
    if (process.platform === 'darwin') {
      // macOS: IOPlatformUUID
      const result = execSync(
        'ioreg -d2 -c IOPlatformExpertDevice | grep IOPlatformUUID',
        { encoding: 'utf8' }
      );
      const match = result.match(/"([^"]+)"/);
      return match ? match[1] : this.fallbackUuid();
    }

    if (process.platform === 'linux') {
      // Linux: machine-id
      try {
        return fs.readFileSync('/etc/machine-id', 'utf8').trim();
      } catch {
        return this.fallbackUuid();
      }
    }

    // Windows or fallback
    return this.fallbackUuid();
  }

  fallbackUuid(): string {
    // use hostname + username as fallback
    return `${os.hostname()}_${os.userInfo().username}`;
  }

  hashUuid(uuid: string): string {
    // create shorter ID from UUID
    return crypto.createHash('sha256').update(uuid).digest('hex').substring(0, 16);
  }

  async registerDevice() {
    const deviceInfo = {
      device_id: this.deviceId,
      hardware_uuid: await this.getHardwareUuid(),
      device_name: os.hostname(),
      device_type: this.getDeviceType(),
      platform: process.platform,
      platform_version: os.release()
    };

    await fetch('https://api.beadster.com/api/devices/register', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(deviceInfo)
    });
  }

  getDeviceType(): string {
    if (process.platform === 'darwin') {
      // could check if it's MacBook, iMac, etc.
      return 'mac';
    }
    if (process.platform === 'linux') return 'linux';
    if (process.platform === 'win32') return 'windows';
    return 'unknown';
  }

  async syncIssueToCloud(issue) {
    // include device info when syncing
    const enriched = {
      ...issue,
      created_by_user_id: this.userId,
      created_by_device_id: this.deviceId,
      created_by_client: 'sync-daemon',
      synced_at: Date.now()
    };

    await this.cloudAPI.upsertIssue(enriched);
  }
}
```

## cloud API

```typescript
// device registration endpoint
app.post('/api/devices/register', async (c) => {
  const user = await authenticate(c);
  const { device_id, hardware_uuid, device_name, device_type, platform, platform_version } = await c.req.json();

  // check if device exists
  let device = await c.env.DB.prepare(`
    SELECT * FROM devices WHERE hardware_uuid = ? AND user_id = ?
  `).bind(hardware_uuid, user.id).first();

  if (!device) {
    // new device - create
    await c.env.DB.prepare(`
      INSERT INTO devices (
        id, user_id, hardware_uuid, device_name, device_type,
        platform, platform_version, first_seen, last_seen
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      device_id,
      user.id,
      hardware_uuid,
      device_name,
      device_type,
      platform,
      platform_version,
      Date.now(),
      Date.now()
    ).run();
  } else {
    // existing device - update last_seen and metadata
    await c.env.DB.prepare(`
      UPDATE devices
      SET last_seen = ?,
          device_name = ?,
          platform_version = ?
      WHERE id = ?
    `).bind(Date.now(), device_name, platform_version, device.id).run();
  }

  return c.json({ device_id });
});

// create issue with device tracking
app.post('/api/issues', async (c) => {
  const user = await authenticate(c);
  const { title, body, device_id, client } = await c.req.json();

  const issueId = ulid();

  await c.env.DB.prepare(`
    INSERT INTO issues (
      id, user_id, title, body,
      created_by_user_id, created_by_device_id, created_by_client,
      created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    issueId,
    user.id,
    title,
    body,
    user.id,
    device_id,
    client || 'web',
    Date.now(),
    Date.now()
  ).run();

  return c.json({ id: issueId });
});

// update issue with device tracking
app.patch('/api/issues/:id', async (c) => {
  const user = await authenticate(c);
  const id = c.req.param('id');
  const { title, body, status, device_id, client } = await c.req.json();

  await c.env.DB.prepare(`
    UPDATE issues
    SET
      title = COALESCE(?, title),
      body = COALESCE(?, body),
      status = COALESCE(?, status),
      updated_by_user_id = ?,
      updated_by_device_id = ?,
      updated_by_client = ?,
      updated_at = ?
    WHERE id = ? AND user_id = ?
  `).bind(
    title,
    body,
    status,
    user.id,
    device_id,
    client || 'web',
    Date.now(),
    id,
    user.id
  ).run();

  return c.json({ success: true });
});

// get user's devices
app.get('/api/devices', async (c) => {
  const user = await authenticate(c);

  const devices = await c.env.DB.prepare(`
    SELECT
      d.*,
      COUNT(i.id) as issue_count,
      MAX(i.created_at) as last_issue_created
    FROM devices d
    LEFT JOIN issues i ON i.created_by_device_id = d.id
    WHERE d.user_id = ?
    GROUP BY d.id
    ORDER BY d.last_seen DESC
  `).bind(user.id).all();

  return c.json(devices);
});
```

## mcp server integration

```typescript
class BeadsterMCP {
  deviceId: string;

  async init() {
    this.deviceId = await this.getDeviceId();
  }

  async getDeviceId(): Promise<string> {
    const configPath = path.join(os.homedir(), '.beadster', 'device.json');

    if (fs.existsSync(configPath)) {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      return config.device_id;
    }

    // sync daemon should have created this
    // if not, create it
    const deviceId = await this.createDeviceId();
    return deviceId;
  }

  async handleCreate(args) {
    // ... existing code ...

    // add device info to labels
    const labels = [
      ...args.labels,
      `device:${this.deviceId}`,
      `client:${await this.getClientType()}`
    ];

    // create issue with bd
    // sync daemon will add device_id when syncing to cloud
  }
}
```

## ui display

show which device created/updated issues:

```astro
---
// issue detail page
const issue = Astro.props.issue;
---

<div class="issue">
  <h3>{issue.title}</h3>
  <div class="metadata">
    <span>created by {issue.created_by_device_name}</span>
    <span>via {issue.created_by_client}</span>
    {issue.updated_by_device_id && (
      <span>last updated from {issue.updated_by_device_name}</span>
    )}
  </div>
</div>
```

```swift
// iOS/Mac app
struct IssueDetailView: View {
  let issue: Issue

  var body: some View {
    VStack(alignment: .leading) {
      Text(issue.title)
        .font(.title)

      HStack {
        Image(systemName: issue.createdByDeviceType == "mac" ? "laptopcomputer" : "iphone")
        Text("created on \(issue.createdByDeviceName)")
          .font(.caption)

        if let updatedDevice = issue.updatedByDeviceName {
          Text("• updated on \(updatedDevice)")
            .font(.caption)
        }
      }
    }
  }
}
```

## benefits

now you can:
- see which device created each issue
- filter issues by device: "show me issues created on my MacBook"
- detect sync conflicts better: "MacBook edited while iPhone edited"
- display device stats: "you've created 45 issues from your MacBook, 12 from your iPhone"
- manage devices: "revoke access from old MacBook"

## device management ui

```astro
---
// pages/devices.astro
const devices = await getDevices(user.id);
---

<h1>your devices</h1>

{devices.map(device => (
  <div class="device">
    <h3>{device.device_name} ({device.device_type})</h3>
    <p>last seen: {formatTime(device.last_seen)}</p>
    <p>created: {device.issue_count} issues</p>
    <button>rename</button>
    <button>remove</button>
  </div>
))}
```

## device identity strategy

user identity:
- who you are
- tracked via apple id
- stable across all devices

device identity:
- which machine
- tracked via hardware uuid
- one per physical device

session identity:
- which conversation
- temporary, per claude session
- helps track context

client identity:
- which app
- "claude-code", "web", "ios-app"
- helps understand usage patterns

all four tracked together:

```typescript
{
  user_id: "apple_user_xyz",           // who
  device_id: "device_abc123",          // which machine
  session_id: "session_789",           // which conversation
  client: "claude-code"                // which app
}
```

this gives full tracking - same pattern for user and device, both stored in cloud, synced everywhere
