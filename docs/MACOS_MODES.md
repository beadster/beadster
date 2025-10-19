# macOS App Modes

beadster macOS app supports two operating modes

## local mode (no authentication)

user can use beadster without signing in

features:
- connect multiple local folders with .beads
- view all issues from all connected folders in one place
- see unified issue list across all projects
- track issues locally in SQLite database
- full bd CLI functionality
- no sync to cloud
- no cross-device access
- data stored only on local machine

use case: privacy-focused users, offline work, local-only projects

## cloud mode (github authenticated)

user signs in with github to enable cloud features

features:
- everything from local mode
- sync issues to cloud (beadster.ai)
- access issues from web interface
- cross-device sync (issues available on all devices)
- share issues with team (future)
- api access for integrations
- backup in cloud

use case: teams, multi-device workflows, web access

## switching between modes

local to cloud:
- click "sign in with github" in settings
- all local issues sync to cloud
- device registered with api_key
- continuous sync enabled

cloud to local:
- click "sign out" in settings
- local database remains intact
- sync stops
- can continue using locally
- can sign back in anytime to resume sync

## technical implementation

local mode:
- uses local SQLite at ~/.beadster/beadster.db
- no api_key needed
- no network requests
- file watcher monitors .beads folders

cloud mode:
- same local SQLite database
- api_key stored in macOS Keychain
- sync daemon sends changes to API
- API validates api_key
- issues synced to D1 database
- accessible via web and API
