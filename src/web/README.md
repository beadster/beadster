# beadster web UI

astro-based web interface for viewing synced beads issues

## features

- view all issues with session tracking badges
- browse sessions grouped by chat/client
- view issues within specific session
- fully server-side rendered (no javascript)
- cloudflare workers deployment

## setup

```bash
npm install
```

copy `.env.example` to `.env` and configure:

```bash
BEADSTER_API_URL=https://beadster-dev-api.your-subdomain.workers.dev
```

## development

```bash
npm run dev
```

## deployment

```bash
npm run deploy
```

or force deploy (bypass tests):

```bash
npm run deploy:force
```

## wrangler config

see `wrangler.jsonc` for cloudflare workers configuration

production: `beadster-web`
development: `beadster-dev-web`

## pages

- `/` - all issues list
- `/sessions` - sessions list
- `/sessions/:id` - session detail with issues
