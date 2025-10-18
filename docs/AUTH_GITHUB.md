# github oauth authentication

authentication for beadster using github oauth

## why github first

target audience: developers
- they already have github accounts
- beadster is dev tool (like linear, github issues)
- no extra signup friction
- can add apple sign in later for consumer use

## flow

web:
```
1. user visits beadster.com
2. clicks "sign in with github"
3. github oauth flow
4. redirect back with code
5. exchange for access token
6. get user info from github
7. create/update user in db
8. set session cookie
```

cli/mcp:
```
1. bd login (or first bd sync)
2. opens browser to beadster.com/cli/auth
3. user signs in with github on web
4. web generates api key
5. cli polls for completion
6. saves api key to ~/.beadster/config
```

macos app:
```
1. app opens with "sign in with github" button
2. opens ASWebAuthenticationSession
3. github oauth in browser
4. redirect back to app with code
5. exchange for tokens
6. save to keychain
```

## github oauth setup

create oauth app at github.com/settings/developers

settings:
- app name: beadster
- homepage: https://beadster.com
- callback url: https://beadster.com/auth/github/callback
- (add localhost:3000 for dev)

credentials:
- client id: stored in wrangler.jsonc env
- client secret: stored in cloudflare secrets

## database schema

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  github_id INTEGER UNIQUE NOT NULL,
  github_login TEXT NOT NULL,
  github_name TEXT,
  github_email TEXT,
  github_avatar_url TEXT,
  api_key TEXT UNIQUE NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_users_github_id ON users(github_id);
CREATE INDEX idx_users_github_login ON users(github_login);
CREATE INDEX idx_users_api_key ON users(api_key);
```

## backend implementation

### install dependencies

```bash
npm install hono @hono/oauth-providers
```

### auth endpoints

```typescript
import { Hono } from 'hono';
import { githubAuth } from '@hono/oauth-providers/github';
import { ulid } from 'ulid';

type Bindings = {
  DB: D1Database;
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_SECRET: string;
  JWT_SECRET: string;
};

const app = new Hono<{ Bindings: Bindings }>();

// start github oauth flow
app.get('/auth/github', (c) => {
  return githubAuth({
    client_id: c.env.GITHUB_CLIENT_ID,
    scope: ['read:user', 'user:email']
  });
});

// github oauth callback
app.get('/auth/github/callback', async (c) => {
  const code = c.req.query('code');

  if (!code) {
    return c.redirect('/?error=missing_code');
  }

  // exchange code for access token
  const tokenResponse = await fetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      client_id: c.env.GITHUB_CLIENT_ID,
      client_secret: c.env.GITHUB_CLIENT_SECRET,
      code
    })
  });

  const { access_token } = await tokenResponse.json();

  // get user info from github
  const userResponse = await fetch('https://api.github.com/user', {
    headers: {
      'Authorization': `Bearer ${access_token}`,
      'Accept': 'application/json'
    }
  });

  const githubUser = await userResponse.json();

  // get user emails
  const emailsResponse = await fetch('https://api.github.com/user/emails', {
    headers: {
      'Authorization': `Bearer ${access_token}`,
      'Accept': 'application/json'
    }
  });

  const emails = await emailsResponse.json();
  const primaryEmail = emails.find((e: any) => e.primary)?.email || githubUser.email;

  // check if user exists
  let user = await c.env.DB.prepare(`
    SELECT * FROM users WHERE github_id = ?
  `).bind(githubUser.id).first();

  const now = Date.now();

  if (!user) {
    // create new user
    const userId = ulid();
    const apiKey = ulid();

    await c.env.DB.prepare(`
      INSERT INTO users (
        id, github_id, github_login, github_name, github_email,
        github_avatar_url, api_key, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      userId,
      githubUser.id,
      githubUser.login,
      githubUser.name,
      primaryEmail,
      githubUser.avatar_url,
      apiKey,
      now,
      now
    ).run();

    user = {
      id: userId,
      github_id: githubUser.id,
      github_login: githubUser.login,
      api_key: apiKey
    };
  } else {
    // update existing user
    await c.env.DB.prepare(`
      UPDATE users SET
        github_login = ?,
        github_name = ?,
        github_email = ?,
        github_avatar_url = ?,
        updated_at = ?
      WHERE github_id = ?
    `).bind(
      githubUser.login,
      githubUser.name,
      primaryEmail,
      githubUser.avatar_url,
      now,
      githubUser.id
    ).run();
  }

  // set session cookie
  const sessionToken = ulid();
  await c.env.DB.prepare(`
    INSERT INTO sessions (id, user_id, expires_at, created_at)
    VALUES (?, ?, ?, ?)
  `).bind(sessionToken, user.id, now + (30 * 24 * 60 * 60 * 1000), now).run();

  c.header('Set-Cookie', `session=${sessionToken}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`);

  return c.redirect('/');
});

// logout
app.get('/auth/logout', async (c) => {
  const sessionToken = getCookie(c, 'session');

  if (sessionToken) {
    await c.env.DB.prepare(`
      DELETE FROM sessions WHERE id = ?
    `).bind(sessionToken).run();
  }

  c.header('Set-Cookie', 'session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0');
  return c.redirect('/');
});

// get current user
app.get('/api/auth/me', async (c) => {
  const user = await authenticate(c);

  if (!user) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  return c.json({
    id: user.id,
    github_login: user.github_login,
    github_name: user.github_name,
    github_email: user.github_email,
    github_avatar_url: user.github_avatar_url
  });
});

// authenticate helper
async function authenticate(c: any) {
  // try session cookie first (web)
  const sessionToken = getCookie(c, 'session');

  if (sessionToken) {
    const session = await c.env.DB.prepare(`
      SELECT u.* FROM users u
      JOIN sessions s ON s.user_id = u.id
      WHERE s.id = ? AND s.expires_at > ?
    `).bind(sessionToken, Date.now()).first();

    if (session) {
      return session;
    }
  }

  // fall back to api key (cli/mcp)
  const apiKey = c.req.header('Authorization')?.replace('Bearer ', '');

  if (apiKey) {
    const user = await c.env.DB.prepare(`
      SELECT * FROM users WHERE api_key = ?
    `).bind(apiKey).first();

    return user;
  }

  return null;
}

function getCookie(c: any, name: string): string | undefined {
  const cookies = c.req.header('Cookie');
  if (!cookies) return undefined;

  const cookie = cookies.split(';').find((c: string) => c.trim().startsWith(`${name}=`));
  return cookie?.split('=')[1];
}
```

### sessions table

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);
```

## cli authentication

```bash
bd login
```

flow:
1. generate auth code
2. open browser to beadster.com/cli/auth?code=xxx
3. user signs in with github
4. web saves api key for that code
5. cli polls /cli/auth/poll?code=xxx
6. returns api key when ready
7. save to ~/.beadster/config

endpoints:

```typescript
// start cli auth
app.get('/cli/auth', async (c) => {
  const code = c.req.query('code');

  if (!code) {
    // generate new code
    const authCode = ulid();
    await c.env.KV.put(`cli_auth:${authCode}`, 'pending', { expirationTtl: 300 });
    return c.redirect(`/cli/auth?code=${authCode}`);
  }

  // show sign in page
  return c.html(`
    <!DOCTYPE html>
    <html>
      <head>
        <title>sign in - beadster</title>
      </head>
      <body>
        <h1>sign in to beadster cli</h1>
        <p>click below to authenticate your terminal</p>
        <a href="/auth/github?cli_code=${code}">
          <button>sign in with github</button>
        </a>
      </body>
    </html>
  `);
});

// modified github callback to handle cli
app.get('/auth/github/callback', async (c) => {
  const code = c.req.query('code');
  const cliCode = c.req.query('state'); // passed via state param

  // ... exchange code for token, get user ...

  if (cliCode) {
    // cli auth flow
    await c.env.KV.put(`cli_auth:${cliCode}`, user.api_key, { expirationTtl: 60 });

    return c.html(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>success - beadster</title>
        </head>
        <body>
          <h1>success!</h1>
          <p>return to your terminal</p>
        </body>
      </html>
    `);
  }

  // regular web flow
  // ... set session cookie ...
  return c.redirect('/');
});

// cli polling endpoint
app.get('/cli/auth/poll', async (c) => {
  const code = c.req.query('code');

  if (!code) {
    return c.json({ error: 'missing code' }, 400);
  }

  const apiKey = await c.env.KV.get(`cli_auth:${code}`);

  if (!apiKey || apiKey === 'pending') {
    return c.json({ status: 'pending' });
  }

  return c.json({ status: 'complete', api_key: apiKey });
});
```

cli implementation:

```bash
#!/bin/bash
# bd login

CODE=$(uuidgen | tr '[:upper:]' '[:lower:]')
echo "opening browser..."
open "https://beadster.com/cli/auth?code=$CODE"

echo "waiting for authentication..."
while true; do
  RESPONSE=$(curl -s "https://beadster.com/cli/auth/poll?code=$CODE")
  STATUS=$(echo $RESPONSE | jq -r .status)

  if [ "$STATUS" = "complete" ]; then
    API_KEY=$(echo $RESPONSE | jq -r .api_key)
    mkdir -p ~/.beadster
    echo "API_KEY=$API_KEY" > ~/.beadster/config
    echo "✓ logged in!"
    break
  fi

  sleep 2
done
```

## macos app authentication

```swift
import AuthenticationServices

class AuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
  func signInWithGitHub() {
    let url = URL(string: "https://beadster.com/auth/github")!
    let callbackScheme = "beadster"

    let session = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: callbackScheme
    ) { callbackURL, error in
      guard let callbackURL = callbackURL else {
        print("auth cancelled or failed: \(error?.localizedDescription ?? "unknown")")
        return
      }

      // extract session token from callback
      // beadster://auth/callback?session=xxx
      if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
         let sessionToken = components.queryItems?.first(where: { $0.name == "session" })?.value {

        // save to keychain
        KeychainHelper.save(sessionToken, for: "beadster_session")

        // fetch user info
        Task {
          await self.fetchUserInfo(sessionToken: sessionToken)
        }
      }
    }

    session.presentationContextProvider = self
    session.start()
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return NSApplication.shared.windows.first!
  }

  func fetchUserInfo(sessionToken: String) async {
    // call /api/auth/me
    var request = URLRequest(url: URL(string: "https://beadster.com/api/auth/me")!)
    request.setValue(sessionToken, forHTTPHeaderField: "Cookie")

    let (data, _) = try await URLSession.shared.data(for: request)
    let user = try JSONDecoder().decode(User.self, from: data)

    // save user info locally
    UserDefaults.standard.set(user.id, forKey: "user_id")
    UserDefaults.standard.set(user.githubLogin, forKey: "github_login")
  }
}
```

callback url handling:

need to register custom url scheme in info.plist:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>beadster</string>
    </array>
  </dict>
</array>
```

## environment variables

add to wrangler.jsonc:

```json
{
  "vars": {
    "GITHUB_CLIENT_ID": "your_github_client_id"
  }
}
```

add secret:

```bash
npx wrangler secret put GITHUB_CLIENT_SECRET
# paste your github client secret
```

## migration plan

phase 1 (now):
- implement github oauth for web
- implement cli auth flow
- implement macos app auth

phase 2 (later):
- add apple sign in for ios/macos
- keep github for web/cli
- users can link both

phase 3 (future):
- add google oauth
- add email/password fallback
- enterprise sso

## testing

local dev:

```bash
# add to .dev.vars
GITHUB_CLIENT_ID=xxx
GITHUB_CLIENT_SECRET=xxx

# update github oauth app callback:
# http://localhost:8787/auth/github/callback
```

test flow:
1. visit localhost:8787
2. click sign in with github
3. authorize app
4. should redirect back and set cookie
5. visit /api/auth/me to see user info
