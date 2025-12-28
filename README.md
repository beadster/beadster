# Beadster

macOS app for browsing and managing issues from `.beads/` directories in your git repositories.

## Features

- Browse git repos and auto-discover projects with `.beads/` directories
- View issues with status, priority, labels
- Create new issues
- Toggle issue status (open/closed)
- File watching with automatic reload
- Works completely offline - no cloud required

## Install

[Download from Mac App Store](https://apps.apple.com/us/app/beadster-issue-tracking/id6754286462)

## Development

Requirements:
- Xcode 16.4+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

Setup:
```bash
cd macos
xcodegen generate
open Beadster.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and not committed to git. Run `xcodegen generate` after pulling changes or modifying `project.yml`.

## License

MIT
