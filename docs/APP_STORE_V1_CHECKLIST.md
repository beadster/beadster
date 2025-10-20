# App Store v1 Readiness Checklist

v1 scope: local-only mode (no authentication, no cloud sync)

## current status

app currently has both local and cloud modes implemented
for v1 submission we need to ensure local mode works perfectly standalone

## must have for v1 submission

### core functionality (all implemented ✅)
- [x] add projects (scan folders for .beads)
- [x] view all issues from all projects
- [x] search and filter issues
- [x] view issue details
- [x] create new issues
- [x] edit issue title, description, status, priority, labels
- [x] close/open issues
- [x] delete issues
- [x] keyboard navigation (up/down, enter)
- [x] file watcher (auto-refresh when .beads changes)
- [x] tree view with dependencies

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

## immediate action items (priority order)

1. **hide cloud UI** (1-2 hours) - CRITICAL
   - hide Account settings section (github sign in)
   - hide sync status footer
   - add build flag or environment variable for LOCAL_ONLY mode

2. **disable sync daemon** (30 min) - CRITICAL
   - skip sync daemon startup in local-only mode
   - ensure no network requests

3. **add onboarding messaging** (30 min)
   - update onboarding to mention "local-only version"
   - add note that cloud sync coming in v2

4. **create app icon** (2-3 hours) - REQUIRED
   - design 1024x1024 icon
   - export all required sizes

5. **create screenshots** (1-2 hours) - REQUIRED
   - take 5-10 screenshots of key features
   - add captions

6. **write app store copy** (1 hour) - REQUIRED
   - description
   - keywords
   - privacy policy

7. **test core flows** (2-3 hours)
   - full user journey from onboarding to creating/editing issues
   - test with 2-3 projects
   - test edge cases

8. **xcode configuration** (1-2 hours) - REQUIRED
   - bundle id, version, signing
   - entitlements
   - build for distribution

9. **final testing on clean mac** (2-3 hours)
   - install on non-dev machine
   - verify no crashes, good performance

10. **submit** (1-2 hours) - FINAL STEP
    - upload to App Store Connect
    - fill metadata
    - submit for review

## estimated total effort

- critical fixes (hide cloud UI, disable sync): 2-3 hours
- required assets (icon, screenshots, copy): 4-6 hours
- testing & polish: 4-6 hours
- xcode setup & submission: 2-3 hours

**total: 12-18 hours** of focused work

## blocking issues (must fix before submission)

1. cloud UI must be hidden (Account section, sync footer)
2. sync daemon must not run in local-only mode
3. app icon required (all sizes)
4. privacy policy required
5. Apple Developer account & signing required
