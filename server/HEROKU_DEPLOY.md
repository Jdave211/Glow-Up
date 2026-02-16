# Heroku Deployment (GlowUp API)

This repo is wired so `git push heroku main` deploys the backend API.

## What is configured

- `Procfile` at repo root runs the server dyno:
  - `web: npm run start:server`
- Root `heroku-postbuild` compiles TypeScript backend:
  - `npm run build:server`
- Server build scope is backend-only (`server/tsconfig.json`) so frontend TSX files do not break deployment.
- Health endpoint:
  - `GET /healthz`
- Heroku metadata:
  - `app.json`
- Slug trimming:
  - `.slugignore` excludes iOS/mobile/training artifacts from slug upload.

## Required config vars

Set these in Heroku:

- `NODE_ENV=production`
- `JWT_SECRET`
- `ROUTINE_SHARE_SECRET`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` or `SUPABASE_SERVICE_ROLE_KEY` (at least one)
- `OPENAI_API_KEY` (recommended for full AI functionality)

Optional but recommended:

- `SUPABASE_SERVICE_ROLE_KEY`
- `GLOWUP_CORS_ORIGINS` (comma-separated allowlist, e.g. `https://app.glowup.ai,https://www.glowup.ai`)
- `GLOWUP_SHARE_BASE_URL`
- `GLOWUP_APP_STORE_URL`
- `GLOWUP_MAX_JSON_BODY` (default `20mb`)

## Deploy commands

```bash
heroku create <your-app-name>
heroku buildpacks:set heroku/nodejs -a <your-app-name>
heroku config:set NODE_ENV=production -a <your-app-name>
heroku config:set JWT_SECRET=... ROUTINE_SHARE_SECRET=... SUPABASE_URL=... SUPABASE_ANON_KEY=... OPENAI_API_KEY=... -a <your-app-name>
git push heroku main
heroku ps:scale web=1 -a <your-app-name>
heroku logs --tail -a <your-app-name>
```

## Verify

```bash
curl https://<your-app-name>.herokuapp.com/healthz
```

Expected shape:

```json
{
  "ok": true,
  "service": "glowup-api"
}
```
