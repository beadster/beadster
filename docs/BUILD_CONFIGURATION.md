# Build Configuration

## local-only mode (v1)

for App Store v1, build with LOCAL_ONLY flag to hide cloud sync features

### enable LOCAL_ONLY flag in Xcode

1. open Beadster.xcodeproj
2. select Beadster target
3. go to Build Settings tab
4. search for "Swift Compiler - Custom Flags"
5. under "Other Swift Flags", add: `-D LOCAL_ONLY`
6. build and run

this will:
- hide Account section in Settings
- hide Sync section in Settings
- hide cloud sync status in footer (left side)
- disable sync daemon (no network requests)

local file watching and project management remain enabled

### revert to full mode (v2+)

remove `-D LOCAL_ONLY` flag from Build Settings

all cloud sync features will be re-enabled
