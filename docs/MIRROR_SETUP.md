# GitHub Mirror Setup

automatic mirroring of public GitHub repositories with beads

## features

- auto-import when signed-in user visits `/{owner}/{repo}`
- read-only mirror (user is not repo owner/collaborator)
- automatic sync every 5 minutes via Cloudflare cron
- displays last sync time and sync frequency in UI
- issues are deduplicated using `external_ref`

## how it works

1. user signs in with GitHub
2. user visits `/owner/repo` for any public GitHub repo with beads
3. system checks if repo has `.beads/issues.jsonl`
4. if found and user is logged in:
   - automatically creates a source (type: `github-mirror`)
   - sets `is_mirror=1`, `auto_sync=1`, `sync_interval_minutes=5`
   - imports all current issues
   - shows "auto-imported to your account" notice
5. Cloudflare cron job runs every 5 minutes:
   - fetches latest issues from GitHub
   - updates changed issues
   - creates new issues
   - updates `last_sync` timestamp
6. UI shows:
   - "read-only mirror" badge
   - sync frequency
   - last sync time
   - link to GitHub repo

## database migration

run this migration to add mirror columns to sources table:

```bash
cd src/web
npx wrangler d1 execute beadster-dev-db --remote --file=migrations/0001_add_mirror_columns.sql
```

or manually:

```sql
ALTER TABLE sources ADD COLUMN is_mirror INTEGER DEFAULT 0;
ALTER TABLE sources ADD COLUMN auto_sync INTEGER DEFAULT 0;
ALTER TABLE sources ADD COLUMN sync_interval_minutes INTEGER DEFAULT 5;
```

## cron setup

cron trigger configured in `wrangler.jsonc`:

```jsonc
"triggers": {
  "crons": ["*/5 * * * *"]
}
```

cron calls API endpoint: `GET /api/cron/sync-mirrors`

endpoint is protected by checking `cf-cron` header (only Cloudflare cron can call it)

## testing

1. deploy web app: `npm run deploy`
2. visit `/beadster/beadster` (or any public repo with beads)
3. should see auto-import notice and mirror badge
4. check database: `SELECT * FROM sources WHERE type='github-mirror'`
5. wait 5 minutes and check if issues are synced
6. check Cloudflare logs for cron execution

## notes

- only public repos are auto-mirrored
- private repos still use manual import flow at `/settings/import`
- mirrors are read-only (no editing allowed in UI)
- sync only happens for sources with `auto_sync=1`
- sync skips repos already synced in last 5 minutes
