# App Store v1 Readiness Checklist

v1 scope: local-only mode (no authentication, no cloud sync)

## current status

app currently has both local and cloud modes implemented
for v1 submission we need to ensure local mode works perfectly standalone

## must have for v1 submission

### core functionality
- [ ] add projects (scan folders for .beads)
- [ ] view all issues from all projects
- [ ] search and filter issues
- [ ] view issue details
- [ ] create new issues
- [ ] edit issue title, description, status, priority, labels
- [ ] close/open issues
- [ ] delete issues
- [ ] keyboard navigation (up/down, enter)
- [ ] file watcher (auto-refresh when .beads changes)
- [ ] tree view with dependencies

### local-only requirements
- [ ] disable or hide cloud sync UI in v1 (sign in button, sync status)
- [ ] ensure app works 100% offline
- [ ] no network requests in local mode
- [ ] clear messaging that this is local-only version
- [ ] data stored only locally in project .beads folders

### stability & polish
- [ ] no crashes or freezes
- [ ] handle edge cases (empty projects, corrupt .beads files)
- [ ] proper error messages (user-friendly, not developer logs)
- [ ] consistent UI/UX across all screens
- [ ] responsive to user actions (no lag)
- [ ] proper memory management (no leaks)
- [ ] works with multiple projects simultaneously

### app metadata
- [ ] app icon (1024x1024)
- [ ] app name: "beadster" or "Beadster"
- [ ] category: Developer Tools
- [ ] description (emphasize local-only, privacy, simplicity)
- [ ] screenshots (5-10 showing key features)
- [ ] keywords for ASO
- [ ] support URL
- [ ] privacy policy (emphasize no data collection, local-only)

### xcode configuration
- [ ] bundle ID set correctly
- [ ] version number (1.0.0)
- [ ] build number
- [ ] deployment target (macOS 13.0+)
- [ ] signing & capabilities configured
- [ ] sandbox entitlements (file access, user selected files)
- [ ] app category in Info.plist
- [ ] minimum system requirements documented

### testing
- [ ] test on clean macOS installation
- [ ] test with multiple projects
- [ ] test with empty state (no projects)
- [ ] test with large number of issues (100+)
- [ ] test folder permissions (sandbox)
- [ ] test file watcher with rapid changes
- [ ] test keyboard shortcuts
- [ ] test search and filters
- [ ] memory leak testing
- [ ] performance testing

### documentation
- [ ] in-app help or onboarding
- [ ] README for users
- [ ] how to add projects
- [ ] how to create issues
- [ ] keyboard shortcuts reference
- [ ] troubleshooting common issues

### legal & compliance
- [ ] privacy policy (can be simple: "we don't collect any data")
- [ ] terms of service (optional for v1)
- [ ] open source licenses if using GPL/LGPL code
- [ ] export compliance (likely "no" for local-only app)

## nice to have (can defer to v1.1)
- [ ] preferences/settings (besides project management)
- [ ] custom keyboard shortcuts
- [ ] export/import functionality
- [ ] issue templates
- [ ] bulk operations
- [ ] undo/redo
- [ ] dark mode refinements
- [ ] accessibility features (VoiceOver, etc)

## post-v1 (cloud mode in v2)
- github authentication
- cloud sync
- web interface access
- multi-device support
- team sharing
- api access

## blocking issues (must fix before submission)

need to audit current code for:
1. any hardcoded cloud sync behavior that runs in local mode
2. network requests that shouldn't happen
3. error handling for missing auth (should gracefully skip)
4. UI elements that reference cloud features

## estimated effort

assuming local mode already works:
- hide cloud UI: 1 hour
- polish & bug fixes: 4-8 hours
- testing: 4 hours
- app store assets (icon, screenshots, text): 4 hours
- xcode configuration: 1 hour
- submission & review response: 2-4 hours

total: 16-24 hours of focused work
