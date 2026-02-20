# Impact Signals — Test & Verification Suite

Automated tests to prevent broken deploys to impactsignals.ai (GitHub Pages).

## Why This Exists

Episode 7 deploy accidentally deleted `style.css`, `robots.txt`, `sitemap.xml`, and other critical files. The site went live without CSS. These tests ensure that **never happens again**.

## Test Scripts

### `test-critical-files.sh` — Pre-Push Validation
Runs locally before any push. Verifies:
- All critical files exist in the repo
- `style.css` is non-empty and contains expected CSS selectors
- `index.html` references `style.css` and has proper structure
- All episode directories have `index.html` files
- `feed.xml` is valid XML
- No episode directories are being deleted in the current commit
- `CNAME` points to `impactsignals.ai`

**Run manually:**
```bash
bash tests/test-critical-files.sh
```

### `test-post-deploy.sh` — Post-Deploy Verification
Runs after pushing. Polls the live site and verifies:
- Site becomes reachable within 90 seconds
- `style.css` returns 200 with correct Content-Type
- `index.html` returns 200 and references `style.css`
- `robots.txt`, `sitemap.xml`, `feed.xml` all return 200
- `feed.xml` response is valid XML
- Latest episode page returns 200
- `style.css` file size matches local copy (within tolerance)

**Run manually:**
```bash
bash tests/test-post-deploy.sh
```

### `test-episode-page.sh <slug>` — Episode Page Verification
Verifies a specific episode page is properly deployed:
- HTTP 200 response
- References `style.css`
- Has proper HTML structure (title, meta tags, OG tags)
- YouTube embed present (if `youtube_id` exists in `episodes.json`)
- Local `index.html` file exists and is non-trivial

**Run manually:**
```bash
bash tests/test-episode-page.sh 7-wfp-grain-atms-google-75m-latam-gpt
```

## Git Hook

The `.githooks/pre-push` hook automatically runs `test-critical-files.sh` before every push.

### Setup (one-time)
```bash
cd /path/to/impactsignal.github.io
git config core.hooksPath .githooks
```

### Bypass (emergency only)
```bash
git push --no-verify
```

## Critical Files List

| File | Why It Matters |
|------|---------------|
| `style.css` | All CSS — without it the site is unstyled |
| `index.html` | Homepage — the main entry point |
| `CNAME` | Custom domain config — without it, site serves from github.io URL |
| `robots.txt` | Search engine directives — SEO |
| `sitemap.xml` | Search engine sitemap — SEO |
| `feed.xml` | Podcast RSS feed — Apple Podcasts, Spotify, etc. |
| `episodes.json` | Episode metadata — used by build scripts |
| `llms.txt` | LLM-readable site summary |
| `llms-full.txt` | Full LLM-readable content |

## Integration with `step-publish-website.sh`

The publishing script automatically:
1. Checks that no critical files are being deleted in the diff
2. Runs `test-critical-files.sh` before pushing (aborts on failure)
3. Runs `test-post-deploy.sh` after pushing (reports but doesn't roll back)
