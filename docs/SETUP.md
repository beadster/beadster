# Beadster Setup Guide

## install beads cli

```bash
git clone https://github.com/steveyegge/beads
cd beads
go build
cp bd /usr/local/bin/
```

verify:

```bash
bd --version
```

## initialize beads in beadster repo

```bash
cd /Users/anton/Dropbox/systemoperator/experiments/beadster
bd init
```

this creates `.beads/` directory for tracking beadster development

## setup api

```bash
cd src/api
npm install

# create d1 database
npm run db:create
# copy database_id to wrangler.jsonc

# run migrations
npm run db:migrate:local

# test locally
npm run dev
```

## setup sync daemon

```bash
cd src/sync
swift build -c release
```

create `~/.beadster/config.json`:

```json
{
  "apiKey": "get-from-api",
  "apiUrl": "http://localhost:8787",
  "sources": [
    {
      "name": "beadster",
      "path": "/Users/anton/Dropbox/systemoperator/experiments/beadster"
    }
  ]
}
```

run:

```bash
swift run
```

## for teams without macOS (github actions idea)

teams can use github actions to sync .beads/ to cloud:

1. add secrets to repo:
   - BEADSTER_API_KEY
   - BEADSTER_API_URL (optional)

2. create workflow that:
   - installs bd cli
   - reads issues: `bd list --json`
   - pushes to api: `POST /api/sync/push`
   - pulls changes: `GET /api/sync/pull`
   - applies via bd: `bd update`
   - commits back to repo

this way non-macOS users can still:
- see issues in web ui
- update issues from web
- have changes sync back to .beads/

## get api key

```bash
curl -X POST http://localhost:8787/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com"}'
```

save the api_key to ~/.beadster/config.json
