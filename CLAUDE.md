# CLAUDE.md

guidance for claude code when working with beadster project

## important

- always use bd track for tasks and todos, never use todowrite tool
- after you complete task use bd to mark it done and commit changes and use closed beads issues ids in the commit message
- when writing markdown keep it simple and readable, don't use bold or italic formatting unless really necessary
- when writing docs keep them minimal unless asked to expand. no water please. docs shouldn't be more than 100 lines in most cases
- in markdown use list with one liners by default and not sections with headers
- when writing lists in docs keep it compact: "need: description here" on one line, not "**need:**" on separate line with bold. use lowercase, no formatting, no blank lines between items
- most product names should be spelled lowercase in docs and code unless specified differently
- by default do not write code for migrations and backwards compatibility. most products are in development and have no users. only ask if product is live and has users
- write code in TypeScript and not JavaScript when working on cloudflare workers code
- use docs/ folder for docs. if there are many docs - create folders in uppercase IDEAS, RESEARCH etc. only split if around 10-20 docs per folder
- name most docs in uppercase, like ARCHITECTURE.md
- task documents can be in lowercase .md files. tasks should be in tasks/todo and tasks/done folders
- when working on TypeScript code try to keep files to 500 lines max. if you see an opportunity, extract code in another file or ask for help
- by default use latest version of npm packages
- when planning tasks or projects skip time estimates
- if you feel not sure about some tradeoff or decision or something doesn't make sense - ask for help

## beads source of truth (CRITICAL)

- .beads/issues.jsonl is the ONLY source of truth for issue data
- .beads/<project>.db is a CACHE rebuilt from JSONL by bd CLI
- macOS app is SANDBOXED and CANNOT execute bd CLI or shell commands
- macOS app MUST write directly to .beads/issues.jsonl when creating/updating/deleting issues
- macOS app reads from .beads/<project>.db for fast queries (cache)
- NEVER try to execute bd CLI from macOS app code - it will fail due to sandbox restrictions
- NEVER add backwards compatibility fallbacks - fail fast if database not found
- database file is named after project (beadster.db, not beads.db)
- use BeadsHelper.findDatabaseFile() to locate database dynamically
- see docs/SOURCE_OF_TRUTH.md for architecture details

## code conventions

- for tests by default use jest
- if you need to create scripts do them in scripts/ folder. when you want to create some script see if one or similar exists
- table names: lowercase, plural (users, projects, lists)
- IDs: use lowercase ULID for all `id` fields
- timestamps: use UNIX timestamps (INTEGER), suffix with `_at` (e.g., `created_at`, `updated_at`)
- required fields: all tables must have `created_at` and `updated_at` by default
- foreign keys: always define constraints for referential integrity

## astro + cloudflare workers

- astro builds _worker.js as directory (not file) containing index.js
- in wrangler.jsonc use: "main": "dist/_worker.js/index.js" (not "dist/_worker.js")
- use exact versions: astro 5.14.4 and @astrojs/cloudflare 12.6.9 (newer versions have [object Object] bug)

deploy:
```bash
npm run deploy     # ALWAYS AND ONLY USE THIS
```

NEVER use `wrangler deploy` directly - it will break the site
NEVER use `astro build` alone - always use full `npm run deploy`

troubleshooting [object Object] bug:
- if deployed worker returns [object Object] instead of HTML:
  - check astro and @astrojs/cloudflare versions (must be 5.14.4 and 12.6.9 exactly)
  - test API endpoints - if they work but .astro pages don't, it's a version issue
  - run: npm install astro@5.14.4 @astrojs/cloudflare@12.6.9 --save-exact
  - redeploy: npm run deploy
- versions 5.14.6+ and 12.6.10+ have regression where astro SSR returns object instead of Response
