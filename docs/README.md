# beadster docs

github for bd (beads issue tracker)

## quick start

[SETUP.md](SETUP.md) - install and configure beadster

## understanding beadster

[OVERVIEW.md](OVERVIEW.md) - what beadster is and how it works

core concept: bd is to git what beadster is to github
- bd: local git-backed issue tracker
- beadster: cloud platform to sync and view all your issues

## using beadster

[USAGE.md](USAGE.md) - how to use beadster in different scenarios

covers:
- coding projects vs inbox tasks
- local vs cloud-only sources
- multi-device workflows
- filtering and views

[AUTO_SETUP.md](AUTO_SETUP.md) - automatic .beads/ creation and registration

covers:
- auto-init in git repos
- auto-registration with sync daemon
- no manual setup needed

## technical details

[DEVICE_TRACKING.md](DEVICE_TRACKING.md) - tracking which device created/updated issues

[IDENTITY_AND_SHARING.md](IDENTITY_AND_SHARING.md) - authentication and sharing

covers:
- sign in with apple
- device registration
- sharing issues

[EXTENDING_BEADS.md](EXTENDING_BEADS.md) - how beadster extends beads without modifying core

covers:
- custom tables (beadster_*)
- sync metadata
- conflict resolution

[SCALING_FOR_TEAMS.md](SCALING_FOR_TEAMS.md) - database backends and team features

covers:
- d1 vs postgresql
- real-time collaboration
- migration path

## implementation

see component READMEs for implementation details:
- [src/api/README.md](../src/api/README.md) - cloudflare workers api
- [src/sync/README.md](../src/sync/README.md) - swift sync daemon
- [src/mcp/README.md](../src/mcp/README.md) - mcp server
- [src/web/README.md](../src/web/README.md) - astro web ui

## file overview

```
docs/
├── README.md              # this file
├── OVERVIEW.md            # what is beadster (start here)
├── SETUP.md               # installation and setup
├── USAGE.md               # usage patterns
├── AUTO_SETUP.md          # auto-init and registration
├── DEVICE_TRACKING.md     # device identity
├── IDENTITY_AND_SHARING.md # auth and sharing
├── EXTENDING_BEADS.md     # technical architecture
└── SCALING_FOR_TEAMS.md   # database and scaling
```

## reading order

new to beadster:
1. OVERVIEW.md - understand the concept
2. SETUP.md - get it running
3. USAGE.md - learn workflow patterns

want technical details:
1. EXTENDING_BEADS.md - architecture
2. DEVICE_TRACKING.md - device identity
3. IDENTITY_AND_SHARING.md - auth
4. SCALING_FOR_TEAMS.md - databases

ready to build:
1. check component READMEs in src/ for implementation
