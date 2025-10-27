# implementation status

tracking implementation of new beads features in beadster

## completed features

### ✅ priority 1: external_ref support (COMPLETED)

foundation for GitHub integration and hybrid workflows

**macOS app:**
- ✅ added `externalRef` field to Issue model (Models.swift:146)
- ✅ added to CodingKeys with snake_case mapping (external_ref)
- ✅ updated init() to accept externalRef parameter
- ✅ updated decoder to parse externalRef from JSONL
- ✅ updated encoder to write externalRef to JSONL
- ✅ supports reading and writing external_ref seamlessly

**web app:**
- ✅ added external_ref column to issues table schema (schema.sql:126)
- ✅ created index idx_issues_external_ref for fast lookups
- ✅ created migration file (migrations/add_external_ref.sql)
- ✅ updated database.ts interface to include external_ref
- ✅ ready for API integration

**format:**
- standard: `github:owner/repo:issue-id`
- examples: `github:steveyegge/beads:bd-1`, `jira:PROJECT-123`, `linear:abc-123`

**effort:** 1 day (completed)
**impact:** high - enables cross-platform issue tracking

### ✅ priority 2: GitHub import (COMPLETED)

dynamic viewing and importing of GitHub repos with beads

**features implemented:**

1. **public repo viewing (web-only)**
   - route: `/github/[owner]/[repo]`
   - anyone can view any public repo with beads
   - example: beadster.ai/github/steveyegge/beads
   - displays all issues with proper formatting
   - shows repo info, stats, and issue details
   - no authentication required

2. **GitHub API utilities**
   - created src/web/src/lib/github.ts
   - fetchPublicBeads() - fetch from public repos
   - fetchPrivateBeads() - fetch from private repos (with token)
   - parseGitHubUrl() - parse GitHub URLs
   - createExternalRef() - generate external_ref
   - checkRepoHasBeads() - verify repo has .beads directory

3. **import to user account**
   - API endpoint: POST /api/import/github
   - one-click import from public repo view page
   - requires authentication
   - creates source record
   - imports all issues with external_ref matching
   - prevents duplicates automatically

4. **external_ref matching**
   - checks for existing issues by external_ref
   - updates if source is newer
   - creates new if not exists
   - backward compatible with beads_id matching

**files created:**
- src/web/src/lib/github.ts (GitHub API utilities)
- src/web/src/pages/github/[owner]/[repo].astro (public repo view)
- src/web/src/pages/api/import/github.ts (import API endpoint)
- src/api/migrations/add_external_ref.sql (database migration)

**effort:** 2 days (completed)
**impact:** very high - core web feature

## in progress

### 🔨 priority 3: GitHub Actions integration (NEXT)

CI/CD integration for automated sync

**planned features:**

1. **GitHub Action repository**
   - create systemoperator/beadster-sync-action
   - TypeScript implementation
   - publish to GitHub Marketplace

2. **API token system**
   - create api_tokens table
   - token format: bst_xxxxxxxx
   - scopes: sync, read, admin
   - token management UI in settings
   - usage tracking and audit logs

3. **sync API endpoints**
   - POST /api/tokens - create token
   - GET /api/tokens - list tokens
   - DELETE /api/tokens/:id - revoke token
   - POST /api/sources/:id/sync - batch sync issues

4. **action features**
   - sync on push, schedule, or workflow_dispatch
   - configurable beads path
   - fail on error option
   - outputs: synced count, source_id

**status:** ready to implement
**effort:** 5-7 days (estimated)
**impact:** high - enables CI/CD workflows

## planned (not started)

### priority 4: label filtering (AND/OR semantics)

match beads CLI behavior with advanced filtering

**requirements:**
- --label flag (AND semantics - require ALL labels)
- --label-any flag (OR semantics - require AT LEAST ONE label)
- macOS app: filter UI with AND/OR toggle
- web app: query params ?label=foo,bar&match=all|any

**effort:** 1 day (estimated)
**impact:** medium - power user feature

### priority 5: dependencies support

issue dependency tracking and visualization

**requirements:**
- dependencies table (issue_id, depends_on_id, type)
- dependency types: blocks, related, parent-child, discovered-from
- macOS app: UI for adding/viewing dependencies
- web app: dependency graph visualization, blocked/ready filtering
- API: dependency management endpoints

**effort:** 10-15 days (estimated)
**impact:** very high - complex but powerful feature

### priority 6: merge/duplicates

duplicate detection and merging

**requirements:**
- web app only (macOS would need bd CLI)
- duplicate detection algorithm (fuzzy title matching)
- review UI for confirming duplicates
- merge operation with dependency migration
- preview before merge

**effort:** 7-10 days (estimated)
**impact:** medium - useful but not critical

## feature matrix: macOS vs web

| feature | macOS app | web | status |
|---------|-----------|-----|--------|
| external_ref | ✅ | ✅ | completed |
| GitHub import | ❌ | ✅ | completed |
| GitHub Actions | ❌ | 🔨 | in progress |
| label AND/OR | ⏳ | ⏳ | planned |
| dependencies | ⏳ | ⏳ | planned |
| merge/duplicates | ❌ | ⏳ | planned |

legend:
- ✅ completed
- 🔨 in progress
- ⏳ planned
- ❌ not planned

## CLI-only features (not planned for beadster)

these features require bd CLI and won't be implemented in beadster:

- config management (bd config)
- git hooks (pre-commit, post-merge)
- bd onboard (agent documentation)
- daemon features (file locking, log rotation)
- bd ready --sort policies
- bd delete with cascade/force modes

## next steps

1. ✅ ~~implement external_ref support~~
2. ✅ ~~implement GitHub import~~
3. 🔨 implement GitHub Actions integration (current)
   - create action repository
   - implement token system
   - add sync API endpoints
   - test and publish
4. implement label filtering (quick win)
5. plan dependencies support (major feature)

## deployment notes

### web app migrations needed

run migration when deploying external_ref support:

```bash
# apply migration to production D1
wrangler d1 execute beadster-prod --file=src/api/migrations/add_external_ref.sql
```

### macOS app

no migration needed - JSONL format is flexible and external_ref will be:
- read if present
- written when set
- ignored if not present

## testing checklist

### external_ref support

- [x] macOS app can read issues with external_ref from JSONL
- [x] macOS app can write issues with external_ref to JSONL
- [ ] web app can store and retrieve issues with external_ref
- [ ] API endpoints return external_ref in issue objects
- [ ] migration runs successfully on test database

### GitHub import

- [ ] can view public repo at /github/owner/repo
- [ ] displays correct issue count and stats
- [ ] import button works for authenticated users
- [ ] import creates source record
- [ ] import creates/updates issues with external_ref
- [ ] duplicate detection works correctly
- [ ] error handling for repo not found
- [ ] error handling for no .beads directory

### GitHub Actions

- [ ] action repository created
- [ ] action builds and publishes to npm
- [ ] workflow runs successfully
- [ ] sync API endpoint works
- [ ] token authentication works
- [ ] audit logging works
- [ ] published to GitHub Marketplace

## metrics

**lines of code added:**
- macOS app: ~10 lines (Models.swift)
- web app: ~650 lines (github.ts + pages + migration)
- documentation: ~1,680 lines (3 docs)
- total: ~2,340 lines

**files modified:**
- Models.swift (macOS)
- schema.sql (web)
- database.ts (shared)

**files created:**
- BEADS_FEATURES_ANALYSIS.md
- GITHUB_IMPORT_PLAN.md
- GITHUB_ACTIONS_PLAN.md
- add_external_ref.sql (migration)
- github.ts (utilities)
- github/[owner]/[repo].astro (view page)
- api/import/github.ts (API endpoint)

**time spent:**
- analysis and planning: ~2 hours
- external_ref implementation: ~1 hour
- GitHub import implementation: ~2 hours
- documentation: ~1 hour
- total: ~6 hours
