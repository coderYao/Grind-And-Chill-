# Grind N Chill Web (Static MVP)

This is a browser-first web version designed for free static hosting and single-user usage.

Last deploy workflow test trigger: 2026-02-20.

## What it includes

- Local-first storage in the browser (`localStorage`)
- Dashboard, Session timer/manual entry, Categories, History, Settings
- JSON export/import compatible with the iOS history payload shape
- Offline caching via service worker
- Storage adapter boundary for future backend sync

## Run locally

From `/Users/shyyao/Dev/IOS Projects/Grind N Chill`:

```bash
cd web
python3 -m http.server 4173
```

Then open `http://localhost:4173`.

## Deploy (static)

You can deploy the `web` folder directly to:

- Cloudflare Pages
- GitHub Pages
- Netlify
- Vercel (Hobby)

No server runtime is required for this MVP.

### Cloudflare Pages CLI flow

From `/Users/shyyao/Dev/IOS Projects/Grind N Chill/web`:

```bash
npm run cf:whoami
npm run cf:deploy
```

`cf:deploy` prepares a clean bundle and deploys to the `main` production branch.
Your stable URL is:

- `https://grind-n-chill-web.pages.dev`

The project is configured in:

- `/Users/shyyao/Dev/IOS Projects/Grind N Chill/web/wrangler.toml`

### GitHub auto-deploy flow

This repo includes:

- `/Users/shyyao/Dev/IOS Projects/Grind N Chill/.github/workflows/deploy-web-pages.yml`

It deploys on pushes to `main` when `web/**` changes.

Required GitHub Actions secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

## Data model and extension point

Current persistence is implemented by:

- `/Users/shyyao/Dev/IOS Projects/Grind N Chill/web/src/storage/localStorageAdapter.js`

Core app logic only talks to the adapter API (`read`, `write`, `clear`).
To add cloud sync later, create another adapter with the same methods and instantiate `AppStore` with that adapter in:

- `/Users/shyyao/Dev/IOS Projects/Grind N Chill/web/src/app.js`

## Notes for single-user usage

- Data is per browser/profile/device.
- Use History JSON export as backup/migration.
- If browser storage is cleared, app data is deleted.
