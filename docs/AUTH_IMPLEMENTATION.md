# Authentication Implementation

complete authentication system for beadster web and macOS apps

## Overview

beadster supports two authentication methods:
- **Better Auth sessions** - for web browser (cookie-based)
- **API keys** - for native macOS app and CLI

## Architecture

### Web (Better Auth)

uses Better Auth with GitHub OAuth provider

flow:
1. user visits beadster.ai
2. clicks "sign in with github"
3. redirects to GitHub OAuth
4. GitHub redirects back to /api/auth/callback/github
5. Better Auth creates user and session
6. session stored in D1, cookie in browser
7. middleware validates session on each request

implementation:
- `src/web/src/lib/auth.ts` - Better Auth configuration
- `src/web/src/pages/api/auth/[...all].ts` - catch-all auth handler
- `src/web/src/middleware.ts` - session validation
- `src/web/src/pages/login.astro` - login page

### macOS App (API Key)

uses GitHub OAuth to get permanent API key

flow:
1. user clicks "sign in with github" in settings
2. opens ASWebAuthenticationSession with beadster.ai
3. completes GitHub OAuth in browser
4. browser redirects to beadster://auth/callback
5. app receives callback
6. app calls /api/auth/api-key endpoint
7. endpoint returns user's permanent api_key
8. app stores api_key in macOS Keychain
9. all future API requests include: `Authorization: Bearer {api_key}`

implementation:
- `src/Beadster/Beadster/Auth/KeychainManager.swift` - Keychain storage
- `src/Beadster/Beadster/Auth/AuthManager.swift` - OAuth flow
- `src/Beadster/Beadster/Views/SettingsView.swift` - UI
- `src/web/src/pages/api/auth/api-key.ts` - API key endpoint
- `src/web/src/middleware.ts` - API key validation

## Database Schema

### users table

```sql
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
```

key fields:
- `api_key` - permanent API key, auto-generated on signup
- `github_id` - GitHub user ID from OAuth
- `github_login` - GitHub username

### sessions table

```sql
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
```

used only for web browser sessions, not for API keys

## Middleware Logic

middleware checks authentication in this order:

1. **API key first** (for native apps):
   - check `Authorization: Bearer {api_key}` header
   - query users table for matching api_key
   - if found, set locals.user

2. **Better Auth session** (for web):
   - check cookies for session token
   - validate session with Better Auth
   - if valid, set locals.user

this allows both methods to work simultaneously

## API Key Management

### Generation

API keys auto-generated on user signup via Better Auth database hook:

```typescript
databaseHooks: {
  user: {
    create: {
      async before(user: any) {
        if (!user.api_key) {
          user.api_key = generateId(); // ULID
        }
        return user;
      }
    }
  }
}
```

### Storage

- **macOS**: stored in macOS Keychain via Security framework
- **CLI** (future): stored in ~/.beadster/config.json
- **Never** stored in git or plain text files

### Retrieval

native apps get API key via `/api/auth/api-key` endpoint:
- requires valid Better Auth session (OAuth just completed)
- returns user's api_key
- app stores in Keychain

### Usage

all API requests from native apps:
```
Authorization: Bearer {api_key}
```

middleware validates and sets user context

## Security

- API keys are permanent (no expiration)
- stored securely in Keychain (macOS) or secure storage
- transmitted over HTTPS only
- validated on every request
- scoped to user (can't access other users' data)
- can be revoked by deleting user or regenerating key

## Two Operating Modes

### Local Mode (No Auth)

- user not signed in
- local SQLite database only
- no API key needed
- no network requests
- all data stays on device

### Cloud Mode (Authenticated)

- user signed in with GitHub
- API key stored in Keychain
- sync daemon uses API key for requests
- data synced to cloud D1 database
- accessible on web and other devices

## Testing

### Test Web Auth

1. go to https://beadster.ai/login
2. click "sign in with github"
3. complete OAuth flow
4. verify redirect to https://beadster.ai
5. verify cookies set
6. verify session persists

### Test macOS Auth

1. build and run macOS app
2. open Settings
3. click "sign in with github"
4. complete OAuth in browser
5. verify redirect to beadster://auth/callback
6. verify "signed in as [user]" shown
7. check Keychain for api_key:
   ```bash
   security find-generic-password -s "com.systemoperator.beadster"
   ```

### Test API Key Auth

1. get api_key from web: https://beadster.ai/api/auth/api-key
2. make API request with key:
   ```bash
   curl -H "Authorization: Bearer {api_key}" \
        https://beadster.ai/api/issues
   ```
3. verify returns user's issues

## Environment Variables

required secrets (set in Cloudflare Workers):
- `BETTER_AUTH_SECRET` - secret for Better Auth sessions
- `GITHUB_CLIENT_SECRET` - GitHub OAuth app secret

public vars (in wrangler.jsonc):
- `BASE_URL` - https://beadster.ai
- `GITHUB_CLIENT_ID` - GitHub OAuth app client ID

## Future Enhancements

- API key rotation
- multiple API keys per user (for different devices)
- API key scopes/permissions
- API key usage tracking
- API key expiration (optional)
- CLI authentication flow
