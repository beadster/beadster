# macOS Auth Implementation Status

current state of GitHub OAuth authentication in macOS app

## ✅ Implemented Components

### 1. KeychainManager (`Auth/KeychainManager.swift`)
- securely stores API key in macOS Keychain
- service: `com.systemoperator.beadster`
- account: `api_key`
- functions: saveAPIKey(), getAPIKey(), deleteAPIKey(), hasAPIKey()

### 2. AuthManager (`Auth/AuthManager.swift`)
- manages GitHub OAuth flow
- published properties: isAuthenticated, currentUser, isLoading, error
- OAuth flow:
  1. POST to `/api/auth/sign-in/social` with provider and callbackURL
  2. receive OAuth URL from server
  3. open ASWebAuthenticationSession with OAuth URL
  4. handle callback at `beadster://callback`
  5. GET `/api/auth/api-key` to fetch user's permanent API key
  6. save API key to Keychain
- uses shared URLSession with cookie storage to maintain session
- functions: signIn(), signOut(), getAPIKey()

### 3. SettingsView Updates
- AccountSettings section added
- shows "sign in with github" button when not authenticated
- shows user info and "sign out" button when authenticated
- displays cloud sync status based on auth state
- integrated with AuthManager.shared

### 4. Web API Endpoints

#### `/api/auth/api-key` (`src/web/src/pages/api/auth/api-key.ts`)
- GET endpoint
- requires valid Better Auth session
- returns user's api_key and profile
- response: `{ api_key: string, user: {...} }`

#### Middleware (`src/web/src/middleware.ts`)
- supports both auth methods:
  1. API key: `Authorization: Bearer {api_key}` header
  2. Better Auth session: cookies
- validates API key by querying users table
- sets locals.user for both methods

### 5. Xcode Project Configuration
- URL scheme configured in project.pbxproj
- `INFOPLIST_KEY_CFBundleURLTypes` added for both Debug and Release
- URL scheme: `beadster://`
- identifier: `ai.beadster.Beadster`

## 🔧 Setup Required

### 1. Add Swift Files to Xcode
the Auth folder with Swift files exists but needs to be added to Xcode:

1. open Beadster.xcodeproj in Xcode
2. Auth files should auto-appear (using PBXFileSystemSynchronizedRootGroup)
3. if not, add them manually:
   - right-click Beadster group
   - Add Files
   - select Auth folder
   - ensure "Create groups" selected

### 2. Update GitHub OAuth App
add macOS callback URL:

1. go to https://github.com/settings/developers
2. select beadster OAuth app
3. add callback URL: `beadster://callback`
4. existing web callback: `https://beadster.ai/api/auth/callback/github`

## 🧪 Testing

### Test Flow
1. build and run app in Xcode
2. open Settings (gear icon)
3. in Account section, click "Sign in with GitHub"
4. browser opens for GitHub authorization
5. after approval, redirects to `beadster://callback`
6. app calls `/api/auth/api-key` to get permanent key
7. API key saved to Keychain
8. Account section shows "Signed in as [name]"
9. Cloud Sync shows "Enabled"

### Verify Keychain
```bash
security find-generic-password -s "com.systemoperator.beadster" -a "api_key" -w
```

### Test API Requests
once authenticated, sync daemon should use API key:
```swift
let apiKey = AuthManager.shared.getAPIKey()
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
```

## 📋 Known Issues

### Cookie Sharing Between ASWebAuthenticationSession and URLSession
- ASWebAuthenticationSession creates OAuth session
- cookies need to be available to subsequent URLSession requests
- current implementation uses HTTPCookieStorage.shared
- may need testing to verify cookie persistence

### User Info Loading
- currently AuthManager.checkAuthentication() only checks if API key exists
- doesn't load user info from local DB or API
- user info only populated after fresh sign-in
- TODO: load user info on app launch if API key exists

## 🚀 Next Steps

### Priority 1: Test OAuth Flow
1. add Swift files to Xcode project
2. update GitHub OAuth callback URLs
3. build and test sign-in flow
4. verify API key saved to Keychain
5. test sign-out

### Priority 2: Integrate with Sync Daemon
1. update SyncDaemon to check AuthManager.isAuthenticated
2. if authenticated, use AuthManager.getAPIKey() for API requests
3. add Authorization header to all sync requests
4. handle 401 responses (sign out)

### Priority 3: Load User Info on Launch
1. add loadUserInfo() function to AuthManager
2. call API with stored api_key to get user profile
3. update currentUser state
4. handle invalid/expired API keys

## 🔐 Security Notes

- API keys stored in macOS Keychain (secure)
- API keys are permanent (no expiration currently)
- API keys scoped to user (can't access other users' data)
- OAuth flow uses secure ASWebAuthenticationSession
- all API requests over HTTPS only
- cookies use secure flag in production
