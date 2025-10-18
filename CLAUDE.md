# CLAUDE.md

guidance for claude code when working with beadster project

## important

- always use bd track for tasks and todos, never use todowrite tool
- after you complete task use bd to mark it done and commit changes
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
- if deployed worker returns [object Object] instead of HTML, check that main points to index.js file
