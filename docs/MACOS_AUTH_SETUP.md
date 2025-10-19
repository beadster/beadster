# macOS App Authentication Setup

setup instructions for GitHub OAuth in beadster macOS app

## Xcode Project Configuration

### 1. Add Swift Files to Xcode

add these new files to the Xcode project:
- `Auth/KeychainManager.swift`
- `Auth/AuthManager.swift`

steps:
1. open beadster.xcodeproj in Xcode
2. right-click on Beadster group
3. select "Add Files to Beadster"
4. select both Auth files
5. ensure "Copy items if needed" is unchecked (files already in place)
6. ensure "Create groups" is selected
7. click Add

### 2. Configure URL Scheme

add custom URL scheme for OAuth callback:

1. open beadster.xcodeproj in Xcode
2. select Beadster target
3. go to Info tab
4. expand "URL Types"
5. click + to add new URL type
6. set:
   - Identifier: `com.systemoperator.beadster`
   - URL Schemes: `beadster`
   - Role: Editor

### 3. Update Info.plist (if needed)

the URL scheme should auto-add to Info.plist, but verify it contains:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.systemoperator.beadster</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>beadster</string>
        </array>
    </dict>
</array>
```

## GitHub OAuth App Configuration

update GitHub OAuth app callback URL:

1. go to https://github.com/settings/developers
2. select beadster OAuth app
3. add callback URL: `beadster://auth/callback`
4. save changes

note: web callback remains `https://beadster.ai/api/auth/callback/github`

## Testing Authentication

### Local Testing

1. build and run app in Xcode
2. open Settings
3. click "Sign in with GitHub"
4. browser opens for GitHub authorization
5. after approval, redirects to `beadster://auth/callback`
6. app receives callback and fetches API key
7. API key saved to macOS Keychain
8. settings show "Signed in as [user]"

### Verify Keychain Storage

check that API key is stored securely:

```bash
security find-generic-password -s "com.systemoperator.beadster" -a "api_key"
```

## API Integration

once authenticated, sync daemon should:
1. get API key from AuthManager
2. include in all API requests: `Authorization: Bearer {api_key}`
3. API validates key and associates requests with user

## Troubleshooting

callback not working:
- verify URL scheme registered in Info.plist
- check GitHub OAuth app callback URL matches
- ensure app is default handler for `beadster://` URLs

API key not saving:
- check Keychain Access permissions
- verify app is signed (required for Keychain access)
- check console for error messages

authentication fails:
- verify GITHUB_CLIENT_SECRET is set in web worker
- check network connectivity
- verify beadster.ai is accessible
