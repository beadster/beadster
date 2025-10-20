# App Store v1 Readiness Checklist

v1 scope: local-only mode (no authentication, no cloud sync)

## remaining work for v1 submission

### local-only requirements
- [ ] hide cloud sync UI (Account section in Settings, sync status footer)
- [ ] disable sync daemon in local-only mode (no network requests)
- [ ] add "local-only version" messaging in onboarding

### app store requirements
- [ ] app icon (1024x1024 + all sizes)
- [ ] screenshots (5-10 showing key features)
- [ ] description (emphasize local-only, privacy)
- [ ] keywords for ASO
- [ ] privacy policy ("no data collection, local-only")
- [ ] support URL (can use github issues)

### xcode configuration
- [ ] bundle ID set correctly
- [ ] version number (1.0.0)
- [ ] build number (1)
- [ ] deployment target (macOS 13.0+ or 14.0+)
- [ ] signing & capabilities (Apple Developer account required)
- [ ] sandbox entitlements (user selected files)
- [ ] app category in Info.plist

### testing
- [ ] test on clean macOS installation
- [ ] test edge cases (empty projects, corrupt files, permission errors)
- [ ] test with multiple projects
- [ ] test with large dataset (100+ issues)
- [ ] memory leak testing
- [ ] performance testing

### legal
- [ ] privacy policy
- [ ] check open source licenses (SwiftGit2 etc)
- [ ] export compliance

## immediate action items (priority order)

1. **hide cloud UI** (1-2 hours) - CRITICAL
   - hide Account settings section
   - hide sync status footer
   - add LOCAL_ONLY build flag

2. **disable sync daemon** (30 min) - CRITICAL
   - skip sync daemon startup
   - no network requests

3. **create app icon** (2-3 hours) - REQUIRED
   - design 1024x1024 icon
   - export all sizes

4. **privacy policy** (30 min) - REQUIRED
   - simple: "no data collection, local-only"

5. **xcode configuration** (1-2 hours) - REQUIRED
   - bundle id, version, signing
   - entitlements

6. **screenshots** (1-2 hours) - REQUIRED
   - 5-10 screenshots
   - add captions

7. **app store copy** (1 hour) - REQUIRED
   - description
   - keywords

8. **testing** (2-3 hours)
   - clean mac installation
   - edge cases

9. **submit** (1-2 hours)
   - upload to App Store Connect
   - submit for review

## estimated effort

- hide cloud UI & disable sync: 2-3 hours
- app icon: 2-3 hours
- screenshots & copy: 2-3 hours
- xcode setup: 1-2 hours
- testing: 2-3 hours
- submission: 1-2 hours

**total: 12-18 hours**

## blocking issues

1. cloud UI must be hidden
2. sync daemon must not run
3. app icon required
4. privacy policy required
5. Apple Developer account required
