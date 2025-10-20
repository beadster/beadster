# App Store v1 Readiness Checklist

v1 scope: local-only mode (no authentication, no cloud sync)

## remaining work for v1 submission

### local-only requirements
- [ ] enable LOCAL_ONLY build flag in Xcode (see docs/BUILD_CONFIGURATION.md)
- [ ] add "local-only version" messaging in onboarding

### app store requirements
- [ ] app icon (1024x1024 + all sizes)
- [ ] screenshots (5-10 showing key features)
- [ ] description (emphasize local-only, privacy)
- [ ] keywords for ASO
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
- [ ] export compliance

## immediate action items (priority order)

1. **create app icon** (2-3 hours) - REQUIRED
   - design 1024x1024 icon
   - export all sizes

2. **xcode configuration** (1-2 hours) - REQUIRED
   - bundle id, version, signing
   - entitlements
   - enable LOCAL_ONLY flag

3. **screenshots** (1-2 hours) - REQUIRED
   - 5-10 screenshots
   - add captions

4. **app store copy** (1 hour) - REQUIRED
   - description
   - keywords

5. **testing** (2-3 hours)
   - clean mac installation
   - edge cases

6. **submit** (1-2 hours)
   - upload to App Store Connect
   - submit for review

## estimated effort

- app icon: 2-3 hours
- screenshots & copy: 2-3 hours
- xcode setup: 1-2 hours
- testing: 2-3 hours
- submission: 1-2 hours

**total: 10-15 hours**

## blocking issues

1. app icon required
2. Apple Developer account required
