# Build Configuration

## local-only mode (v1)

for App Store v1, cloud sync is disabled via runtime configuration

### configuration

edit `Shared/AppConfig.swift`:

```swift
enum AppConfig {
    /// Enable cloud sync features (authentication, sync daemon, API calls)
    /// Set to false for local-only App Store v1 release
    static let cloudSyncEnabled = false

    /// Enable GitHub integration UI
    /// Set to false for App Store v1 release
    static let githubIntegrationEnabled = false
}
```

when `cloudSyncEnabled = false`:
- hides Account section in Settings
- hides Sync section in Settings
- hides cloud sync status in footer (left side)
- disables cloud sync in sync daemon (no network requests)
- keeps local file watching and project management enabled

### enable full mode (v2+)

set `cloudSyncEnabled = true` in AppConfig.swift

all cloud sync features will be re-enabled
