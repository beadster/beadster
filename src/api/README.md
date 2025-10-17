# Beadster API

Cloudflare Workers backend for Beadster

## setup

```bash
npm install
```

## create d1 database

```bash
npm run db:create
# copy database_id from output to wrangler.jsonc
```

## run migrations

```bash
# local
npm run db:migrate:local

# production
npm run db:migrate
```

## development

```bash
npm run dev
# api available at http://localhost:8787
```

## deploy

```bash
npm run deploy
```

## endpoints

### auth
- `POST /api/auth/register` - register/get api key

### sync (for daemon)
- `POST /api/sync/push` - push issues from local .beads/
- `GET /api/sync/pull` - pull changes from cloud

### web
- `GET /api/issues` - list all issues
- `GET /api/sessions` - list sessions
- `GET /api/sessions/:id/issues` - list issues in session

## example usage

### register
```bash
curl -X POST https://api.beadster.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com"}'
```

### push issues
```bash
curl -X POST https://api.beadster.com/api/sync/push \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @payload.json
```

### list issues
```bash
curl "https://api.beadster.com/api/issues?api_key=YOUR_API_KEY"
```
