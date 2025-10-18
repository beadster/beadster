# Identity, Authentication, and Sharing in beadster

## Apple ID Authentication

### Sign in with Apple for Mac/iOS Apps

**Perfect fit for beadster:**

```swift
import AuthenticationServices

class AuthManager: NSObject, ASAuthorizationControllerDelegate {
  func signInWithApple() {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.fullName, .email]

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = self
    controller.performRequests()
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
      // Got Apple ID credential
      let userID = credential.user  // Stable, unique user identifier
      let email = credential.email
      let fullName = credential.fullName

      // Exchange with beadster backend
      Task {
        await exchangeAppleCredentialForToken(
          userID: userID,
          identityToken: credential.identityToken,
          authorizationCode: credential.authorizationCode
        )
      }
    }
  }

  func exchangeAppleCredentialForToken(
    userID: String,
    identityToken: Data?,
    authorizationCode: Data?
  ) async {
    // Send to beadster API
    let response = try await URLSession.shared.data(
      for: URLRequest(url: URL(string: "https://api.beadster.com/auth/apple")!)
        .with(method: "POST")
        .with(body: [
          "user_id": userID,
          "identity_token": identityToken?.base64EncodedString(),
          "authorization_code": authorizationCode?.base64EncodedString()
        ])
    )

    let auth = try JSONDecoder().decode(AuthResponse.self, from: response.0)

    // Save tokens
    KeychainHelper.save(auth.accessToken, for: "beadster_access_token")
    KeychainHelper.save(auth.refreshToken, for: "beadster_refresh_token")

    // Store user ID
    UserDefaults.standard.set(userID, forKey: "beadster_user_id")
  }
}
```

### Backend (Cloudflare Workers)

```typescript
// api.beadster.com/auth/apple

import { Hono } from 'hono';
import jwt from '@tsndr/cloudflare-worker-jwt';

const app = new Hono();

app.post('/auth/apple', async (c) => {
  const { user_id, identity_token, authorization_code } = await c.req.json();

  // Verify Apple identity token
  const applePublicKey = await getApplePublicKey();
  const verified = await jwt.verify(identity_token, applePublicKey);

  if (!verified) {
    return c.json({ error: 'Invalid token' }, 401);
  }

  // Decode to get user info
  const decoded = jwt.decode(identity_token);
  const appleUserId = decoded.payload.sub;

  // Check if user exists
  let user = await c.env.DB.prepare(`
    SELECT * FROM users WHERE apple_id = ?
  `).bind(appleUserId).first();

  if (!user) {
    // Create new user
    const userId = crypto.randomUUID();
    const apiKey = generateApiKey();

    await c.env.DB.prepare(`
      INSERT INTO users (id, apple_id, email, api_key, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).bind(
      userId,
      appleUserId,
      decoded.payload.email,
      apiKey,
      Date.now()
    ).run();

    user = { id: userId, apple_id: appleUserId, api_key: apiKey };
  }

  // Generate access token
  const accessToken = await jwt.sign(
    {
      user_id: user.id,
      apple_id: user.apple_id,
      exp: Math.floor(Date.now() / 1000) + (60 * 60 * 24 * 7) // 7 days
    },
    c.env.JWT_SECRET
  );

  // Generate refresh token
  const refreshToken = await jwt.sign(
    {
      user_id: user.id,
      type: 'refresh',
      exp: Math.floor(Date.now() / 1000) + (60 * 60 * 24 * 90) // 90 days
    },
    c.env.JWT_SECRET
  );

  return c.json({
    access_token: accessToken,
    refresh_token: refreshToken,
    user_id: user.id,
    api_key: user.api_key
  });
});
```

### Database Schema

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  apple_id TEXT UNIQUE,  -- From Sign in with Apple
  email TEXT,
  name TEXT,
  api_key TEXT UNIQUE NOT NULL,  -- For CLI/MCP access
  created_at INTEGER,
  updated_at INTEGER
);

CREATE INDEX idx_users_apple_id ON users(apple_id);
CREATE INDEX idx_users_api_key ON users(api_key);
```

### CLI Authentication

**For CLI users (brew install beadster):**

```bash
beadster login

# Opens browser to beadster.com/cli/auth
# User signs in with Apple ID on web
# Web returns code
# CLI exchanges code for API key
# Saves to ~/.beadster/config.json
```

**Backend:**

```typescript
app.get('/cli/auth', async (c) => {
  const code = crypto.randomUUID();

  // Store code temporarily
  await c.env.KV.put(`auth_code:${code}`, '', { expirationTtl: 300 });

  return c.html(`
    <html>
      <body>
        <h1>Sign in with Apple</h1>
        <button id="signin">Continue with Apple</button>
        <script>
          // Sign in with Apple JS SDK
          document.getElementById('signin').onclick = () => {
            AppleID.auth.signIn({
              clientId: 'com.beadster.auth',
              redirectURI: 'https://api.beadster.com/auth/apple/callback',
              state: '${code}',
              scope: 'email name'
            });
          };
        </script>
      </body>
    </html>
  `);
});

app.get('/auth/apple/callback', async (c) => {
  const { code: authCode, state } = c.req.query();

  // Exchange auth code for user info
  const user = await verifyAppleAuthCode(authCode);

  // Store API key for CLI
  await c.env.KV.put(`auth_code:${state}`, user.api_key, { expirationTtl: 60 });

  return c.html(`
    <html>
      <body>
        <h1>Success!</h1>
        <p>Return to your terminal.</p>
      </body>
    </html>
  `);
});

app.get('/cli/auth/poll', async (c) => {
  const { code } = c.req.query();

  const apiKey = await c.env.KV.get(`auth_code:${code}`);

  if (!apiKey) {
    return c.json({ status: 'pending' });
  }

  return c.json({ status: 'complete', api_key: apiKey });
});
```

**CLI polls for completion:**

```bash
#!/bin/bash
# beadster login

CODE=$(curl -s https://api.beadster.com/cli/auth/start | jq -r .code)
echo "Opening browser..."
open "https://api.beadster.com/cli/auth?code=$CODE"

echo "Waiting for authentication..."
while true; do
  RESPONSE=$(curl -s "https://api.beadster.com/cli/auth/poll?code=$CODE")
  STATUS=$(echo $RESPONSE | jq -r .status)

  if [ "$STATUS" = "complete" ]; then
    API_KEY=$(echo $RESPONSE | jq -r .api_key)
    echo "API_KEY=$API_KEY" > ~/.beadster/config
    echo "✓ Logged in!"
    break
  fi

  sleep 2
done
```

## Sharing Tasks

### Source-Level Sharing

**Share entire source (project):**

```sql
CREATE TABLE source_shares (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  shared_with_user_id TEXT,  -- Specific user
  shared_with_email TEXT,    -- Or by email (pending)
  permission TEXT NOT NULL,  -- 'read', 'write', 'admin'
  created_at INTEGER,
  accepted_at INTEGER,
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (owner_id) REFERENCES users(id),
  FOREIGN KEY (shared_with_user_id) REFERENCES users(id)
);

CREATE INDEX idx_source_shares_source ON source_shares(source_id);
CREATE INDEX idx_source_shares_user ON source_shares(shared_with_user_id);
CREATE INDEX idx_source_shares_email ON source_shares(shared_with_email);
```

**API:**

```typescript
// Share a source
app.post('/api/sources/:id/share', async (c) => {
  const user = await authenticate(c);
  const sourceId = c.req.param('id');
  const { email, permission } = await c.req.json();

  // Check ownership
  const source = await c.env.DB.prepare(`
    SELECT * FROM sources WHERE id = ? AND user_id = ?
  `).bind(sourceId, user.id).first();

  if (!source) {
    return c.json({ error: 'Not found' }, 404);
  }

  // Look up user by email
  const targetUser = await c.env.DB.prepare(`
    SELECT * FROM users WHERE email = ?
  `).bind(email).first();

  const shareId = crypto.randomUUID();

  await c.env.DB.prepare(`
    INSERT INTO source_shares (
      id, source_id, owner_id, shared_with_user_id, shared_with_email,
      permission, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).bind(
    shareId,
    sourceId,
    user.id,
    targetUser?.id,
    email,
    permission,
    Date.now()
  ).run();

  // Send notification
  if (targetUser) {
    await sendNotification(targetUser.id, {
      type: 'source_shared',
      source_id: sourceId,
      source_name: source.name,
      from_user: user.name || user.email,
      permission
    });
  } else {
    // Send invite email
    await sendInviteEmail(email, {
      source_name: source.name,
      from_user: user.name || user.email
    });
  }

  return c.json({ share_id: shareId });
});

// List shared sources
app.get('/api/sources/shared', async (c) => {
  const user = await authenticate(c);

  const shared = await c.env.DB.prepare(`
    SELECT
      s.*,
      sh.permission,
      sh.owner_id,
      u.name as owner_name,
      u.email as owner_email
    FROM sources s
    JOIN source_shares sh ON sh.source_id = s.id
    JOIN users u ON u.id = sh.owner_id
    WHERE sh.shared_with_user_id = ?
  `).bind(user.id).all();

  return c.json(shared);
});
```

**UI (Mac app):**

```swift
struct SourceDetailView: View {
  @State var source: Source
  @State var showShareSheet = false

  var body: some View {
    VStack {
      HStack {
        Text(source.name)
          .font(.title)

        Spacer()

        Button(action: { showShareSheet = true }) {
          Image(systemName: "person.badge.plus")
        }
      }

      // Issues list...
    }
    .sheet(isPresented: $showShareSheet) {
      ShareSourceView(source: source)
    }
  }
}

struct ShareSourceView: View {
  let source: Source
  @State var email = ""
  @State var permission = "read"

  var body: some View {
    Form {
      Section("Share with") {
        TextField("Email", text: $email)
        Picker("Permission", selection: $permission) {
          Text("Read only").tag("read")
          Text("Can edit").tag("write")
          Text("Admin").tag("admin")
        }
      }

      Button("Share") {
        Task {
          await shareSource(source.id, email: email, permission: permission)
        }
      }
    }
  }
}
```

### Issue-Level Sharing

**Share specific issue (public link):**

```sql
CREATE TABLE issue_shares (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  source_id TEXT NOT NULL,
  created_by TEXT NOT NULL,
  public_token TEXT UNIQUE,  -- For public links
  expires_at INTEGER,
  view_count INTEGER DEFAULT 0,
  FOREIGN KEY (issue_id) REFERENCES issues(id),
  FOREIGN KEY (source_id) REFERENCES sources(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE INDEX idx_issue_shares_token ON issue_shares(public_token);
```

**API:**

```typescript
app.post('/api/issues/:id/share', async (c) => {
  const user = await authenticate(c);
  const issueId = c.req.param('id');

  const issue = await getIssue(issueId);

  // Generate public token
  const token = crypto.randomUUID();

  await c.env.DB.prepare(`
    INSERT INTO issue_shares (id, issue_id, source_id, created_by, public_token)
    VALUES (?, ?, ?, ?, ?)
  `).bind(crypto.randomUUID(), issueId, issue.source_id, user.id, token).run();

  const url = `https://beadster.com/share/${token}`;

  return c.json({ url });
});

// Public view (no auth required)
app.get('/share/:token', async (c) => {
  const token = c.req.param('token');

  const share = await c.env.DB.prepare(`
    SELECT
      i.*,
      s.name as source_name,
      sh.view_count
    FROM issue_shares sh
    JOIN issues i ON i.id = sh.issue_id
    JOIN sources s ON s.id = sh.source_id
    WHERE sh.public_token = ?
      AND (sh.expires_at IS NULL OR sh.expires_at > ?)
  `).bind(token, Date.now()).first();

  if (!share) {
    return c.html('<h1>Link expired or not found</h1>', 404);
  }

  // Increment view count
  await c.env.DB.prepare(`
    UPDATE issue_shares SET view_count = view_count + 1
    WHERE public_token = ?
  `).run(token);

  return c.html(`
    <html>
      <head>
        <title>${share.title} - beadster</title>
      </head>
      <body>
        <h1>${share.title}</h1>
        <p><strong>Source:</strong> ${share.source_name}</p>
        <p><strong>Status:</strong> ${share.status}</p>
        <p><strong>Priority:</strong> ${share.priority}</p>
        <div>${share.body}</div>
        <p><small>Shared via beadster</small></p>
      </body>
    </html>
  `);
});
```

## Linking to Claude Code Logs

### Capturing Log Context

**Store log references in beadster extension table (in .beads/beads.db):**

```sql
-- in .beads/beads.db (beadster extension table)
CREATE TABLE beadster_context (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  context_type TEXT NOT NULL,  -- 'claude_log', 'screenshot', 'file', 'conversation'

  -- For Claude logs
  log_path TEXT,
  log_line_start INTEGER,
  log_line_end INTEGER,
  log_excerpt TEXT,  -- First 500 chars

  -- For conversations
  conversation_id TEXT,
  conversation_title TEXT,

  -- For files
  file_path TEXT,
  file_line INTEGER,

  -- For screenshots
  screenshot_path TEXT,

  -- Common
  created_at INTEGER,

  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

CREATE INDEX idx_beadster_context_issue ON beadster_context(issue_id);
CREATE INDEX idx_beadster_context_type ON beadster_context(context_type);
```

### MCP Server Captures Context

**When creating issue:**

```typescript
class beadsterMCP {
  async todo_create(params) {
    // Create issue via bd
    const issueId = await this.createIssueWithBd(params);

    // Capture context
    await this.captureContext(issueId);

    return issueId;
  }

  async captureContext(issueId: string) {
    const beadsDir = await this.findBeadsDir();
    const db = new Database(`${beadsDir}/beads.db`);

    // 1. Capture current Claude Code log
    const logPath = await this.findCurrentLogFile();
    if (logPath) {
      const excerpt = await this.readLogExcerpt(logPath);

      db.prepare(`
        INSERT INTO beadster_context (
          id, issue_id, context_type, log_path, log_excerpt, created_at
        )
        VALUES (?, ?, 'claude_log', ?, ?, ?)
      `).run(
        crypto.randomUUID(),
        issueId,
        logPath,
        excerpt,
        Date.now()
      );
    }

    // 2. Capture conversation ID (if available)
    const conversationId = await this.getConversationId();
    if (conversationId) {
      db.prepare(`
        INSERT INTO beadster_context (
          id, issue_id, context_type, conversation_id, created_at
        )
        VALUES (?, ?, 'conversation', ?, ?)
      `).run(crypto.randomUUID(), issueId, conversationId, Date.now());
    }

    // 3. Capture current file context
    const fileContext = await this.getCurrentFileContext();
    if (fileContext) {
      db.prepare(`
        INSERT INTO beadster_context (
          id, issue_id, context_type, file_path, file_line, created_at
        )
        VALUES (?, ?, 'file', ?, ?, ?)
      `).run(
        crypto.randomUUID(),
        issueId,
        fileContext.path,
        fileContext.line,
        Date.now()
      );
    }
  }

  async findCurrentLogFile(): Promise<string | null> {
    // Claude Code logs location
    const logDir = path.join(
      os.homedir(),
      'Library/Logs/Claude'
    );

    if (!fs.existsSync(logDir)) {
      return null;
    }

    // Find most recent .claude file
    const files = fs.readdirSync(logDir)
      .filter(f => f.endsWith('.claude'))
      .map(f => ({
        path: path.join(logDir, f),
        mtime: fs.statSync(path.join(logDir, f)).mtime
      }))
      .sort((a, b) => b.mtime.getTime() - a.mtime.getTime());

    return files[0]?.path || null;
  }

  async readLogExcerpt(logPath: string): Promise<string> {
    // Read last 50 lines or 500 chars
    const content = fs.readFileSync(logPath, 'utf8');
    const lines = content.split('\n').slice(-50);
    const excerpt = lines.join('\n').slice(-500);
    return excerpt;
  }

  async getConversationId(): Promise<string | null> {
    // Try to get from environment or process
    const conversationId = process.env.CLAUDE_CONVERSATION_ID;
    return conversationId || null;
  }
}
```

### Viewing Context in UI

**Mac app shows context:**

```swift
struct IssueDetailView: View {
  let issue: Issue
  @State var contexts: [Context] = []

  var body: some View {
    VStack(alignment: .leading) {
      Text(issue.title)
        .font(.title)

      Text(issue.body)
        .padding()

      if !contexts.isEmpty {
        Divider()

        Text("Context")
          .font(.headline)

        ForEach(contexts) { context in
          ContextView(context: context)
        }
      }
    }
    .onAppear {
      loadContexts()
    }
  }

  func loadContexts() {
    // Load from beadster_context table
    contexts = beadsterDatabase.shared.getContexts(for: issue.id)
  }
}

struct ContextView: View {
  let context: Context

  var body: some View {
    HStack {
      Image(systemName: iconForType(context.type))

      VStack(alignment: .leading) {
        Text(titleForType(context.type))
          .font(.caption)
          .foregroundColor(.secondary)

        switch context.type {
        case .claudeLog:
          Text(context.logPath ?? "")
            .font(.caption2)
          if let excerpt = context.logExcerpt {
            Text(excerpt)
              .font(.system(.caption2, design: .monospaced))
              .lineLimit(3)
          }
          Button("View Full Log") {
            openLog(context.logPath)
          }

        case .conversation:
          Text("Conversation: \(context.conversationId ?? "")")
          Button("Open in Claude") {
            // Deep link to conversation
            openConversation(context.conversationId)
          }

        case .file:
          Text("\(context.filePath ?? ""):\(context.fileLine ?? 0)")
          Button("Open File") {
            openFile(context.filePath, line: context.fileLine)
          }

        case .screenshot:
          AsyncImage(url: URL(fileURLWithPath: context.screenshotPath ?? ""))
            .frame(width: 200, height: 150)
          Button("View Full Size") {
            openScreenshot(context.screenshotPath)
          }
        }
      }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(8)
  }

  func iconForType(_ type: ContextType) -> String {
    switch type {
    case .claudeLog: return "doc.text"
    case .conversation: return "message"
    case .file: return "doc"
    case .screenshot: return "photo"
    }
  }
}
```

### Log File Management

**Storing logs:**

```
Option 1: Keep references only (recommended)
- Store path to .claude file
- Don't copy/move
- User keeps logs in ~/Library/Logs/Claude
- App reads on demand

Option 2: Copy excerpts to cloud
- When syncing issue, upload log excerpt
- Store in cloud storage (R2)
- Can view from any device

Option 3: Hybrid
- Store path locally
- Upload excerpt to cloud for viewing on other devices
```

**Schema for cloud storage:**

```sql
-- In cloud database
CREATE TABLE issue_context (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  context_type TEXT NOT NULL,

  -- Log data
  log_excerpt TEXT,
  log_full_url TEXT,  -- R2 URL if full log uploaded

  -- File context
  file_path TEXT,
  file_line INTEGER,
  file_content TEXT,  -- Snippet

  -- Screenshot
  screenshot_url TEXT,  -- R2 URL

  created_at INTEGER,

  FOREIGN KEY (issue_id) REFERENCES issues(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
```

**Upload to R2:**

```typescript
async function uploadLogContext(issueId: string, logPath: string) {
  // Read log file
  const content = fs.readFileSync(logPath, 'utf8');

  // Upload to R2
  const key = `logs/${issueId}/${Date.now()}.txt`;
  await env.R2.put(key, content);

  // Get public URL
  const url = `https://beadster-logs.r2.dev/${key}`;

  // Store in database
  await env.DB.prepare(`
    INSERT INTO issue_context (
      id, issue_id, user_id, context_type, log_full_url, created_at
    )
    VALUES (?, ?, ?, 'claude_log', ?, ?)
  `).run(crypto.randomUUID(), issueId, userId, url, Date.now());
}
```

## Summary

### Identity & Auth

1. **Sign in with Apple** for Mac/iOS apps
   - Seamless authentication
   - Privacy-focused
   - No password management

2. **API keys** for CLI/MCP
   - Generate via web auth
   - Store in ~/.beadster/config
   - Long-lived tokens

3. **Database schema** tracks Apple ID + API keys

### Sharing

1. **Source-level sharing**
   - Share entire project with collaborators
   - Permissions: read/write/admin
   - Invite by email

2. **Issue-level sharing**
   - Public links for specific issues
   - No auth required
   - Expire after time
   - Track view counts

3. **UI in Mac/iOS apps** for easy sharing

### Log Context

1. **Auto-capture** when creating issues
   - Claude Code log file reference
   - Conversation ID
   - Current file + line
   - Screenshots

2. **Store in beadster_context table**
   - References to local logs
   - Excerpts for quick view
   - Full logs optional (upload to R2)

3. **View in UI**
   - See log excerpts
   - Open full log file
   - Deep link to conversations
   - Open files at exact line

**All three features integrate seamlessly with the beadster extension model!**
