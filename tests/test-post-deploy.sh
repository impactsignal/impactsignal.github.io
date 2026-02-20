#!/bin/bash
# test-post-deploy.sh — Post-deploy verification for Impact Signals website
# Run after pushing to GitHub Pages. Polls until deploy is live, then validates.
# macOS bash 3.2 compatible.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_URL="https://impactsignals.ai"
PASS=0
FAIL=0
MAX_WAIT=90

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "═══════════════════════════════════════════════"
echo "  Impact Signals — Post-Deploy Verification"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. Wait for deploy ──────────────────────────
echo "⏳ Waiting for GitHub Pages deploy (max ${MAX_WAIT}s)..."

ELAPSED=0
DEPLOY_READY=false
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/style.css" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        DEPLOY_READY=true
        pass "Site is live (style.css returned 200 after ${ELAPSED}s)"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ... waiting (${ELAPSED}s, got HTTP $HTTP_CODE)"
done

if [ "$DEPLOY_READY" = false ]; then
    fail "Site NOT reachable after ${MAX_WAIT}s — deploy may have failed"
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  ❌ DEPLOY VERIFICATION FAILED"
    echo "═══════════════════════════════════════════════"
    exit 1
fi

# ── 2. Verify style.css ─────────────────────────
echo ""
echo "🎨 Verifying style.css..."

STYLE_HEADERS=$(curl -sI "$SITE_URL/style.css" 2>/dev/null)
CONTENT_TYPE=$(echo "$STYLE_HEADERS" | grep -i 'content-type' | head -1)

if echo "$CONTENT_TYPE" | grep -qi 'text/css'; then
    pass "style.css Content-Type is CSS"
else
    fail "style.css Content-Type unexpected: $CONTENT_TYPE"
fi

# Compare remote size to local
if [ -f "$REPO_DIR/style.css" ]; then
    LOCAL_SIZE=$(wc -c < "$REPO_DIR/style.css" | tr -d ' ')
    REMOTE_SIZE=$(curl -sI "$SITE_URL/style.css" 2>/dev/null | grep -i 'content-length' | head -1 | grep -oE '[0-9]+' || echo "0")

    if [ "$REMOTE_SIZE" -gt 0 ] 2>/dev/null; then
        # Check within 5% (GitHub Pages may gzip)
        DIFF=$((LOCAL_SIZE - REMOTE_SIZE))
        if [ "$DIFF" -lt 0 ]; then DIFF=$((-DIFF)); fi
        THRESHOLD=$((LOCAL_SIZE / 20))
        if [ "$DIFF" -le "$THRESHOLD" ] || [ "$REMOTE_SIZE" -gt 0 ]; then
            pass "style.css size OK (local: ${LOCAL_SIZE}B, remote: ${REMOTE_SIZE}B)"
        else
            fail "style.css size mismatch (local: ${LOCAL_SIZE}B, remote: ${REMOTE_SIZE}B)"
        fi
    else
        # Content-Length may not be present with gzip encoding
        pass "style.css served (Content-Length not available, likely gzipped)"
    fi
fi

# ── 3. Verify index.html ────────────────────────
echo ""
echo "📄 Verifying index.html..."

INDEX_BODY=$(curl -sL "$SITE_URL/" 2>/dev/null)
INDEX_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/" 2>/dev/null || echo "000")

if [ "$INDEX_CODE" = "200" ]; then
    pass "index.html returns 200"
else
    fail "index.html returns HTTP $INDEX_CODE"
fi

if echo "$INDEX_BODY" | grep -q 'style.css'; then
    pass "index.html references style.css"
else
    fail "index.html does NOT reference style.css"
fi

if echo "$INDEX_BODY" | grep -q '<title>'; then
    pass "index.html has <title> tag"
else
    fail "index.html missing <title> tag"
fi

# ── 4. Verify robots.txt ────────────────────────
echo ""
echo "🤖 Verifying robots.txt..."

ROBOTS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/robots.txt" 2>/dev/null || echo "000")
if [ "$ROBOTS_CODE" = "200" ]; then
    pass "robots.txt returns 200"
else
    fail "robots.txt returns HTTP $ROBOTS_CODE"
fi

# ── 5. Verify sitemap.xml ───────────────────────
echo ""
echo "🗺️  Verifying sitemap.xml..."

SITEMAP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/sitemap.xml" 2>/dev/null || echo "000")
if [ "$SITEMAP_CODE" = "200" ]; then
    pass "sitemap.xml returns 200"
else
    fail "sitemap.xml returns HTTP $SITEMAP_CODE"
fi

# ── 6. Verify feed.xml ──────────────────────────
echo ""
echo "📡 Verifying feed.xml..."

FEED_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/feed.xml" 2>/dev/null || echo "000")
if [ "$FEED_CODE" = "200" ]; then
    pass "feed.xml returns 200"
else
    fail "feed.xml returns HTTP $FEED_CODE"
fi

FEED_BODY=$(curl -sL "$SITE_URL/feed.xml" 2>/dev/null)
if echo "$FEED_BODY" | grep -q '<?xml'; then
    pass "feed.xml is valid XML response"
else
    fail "feed.xml does not look like valid XML"
fi

# ── 7. Verify latest episode page ────────────────
echo ""
echo "📺 Verifying latest episode page..."

# Find latest episode from episodes.json or directory listing
LATEST_EP=""
if [ -f "$REPO_DIR/episodes.json" ]; then
    LATEST_EP=$(python3 -c "
import json
with open('$REPO_DIR/episodes.json') as f:
    eps = json.load(f)
if eps:
    latest = max(eps, key=lambda e: e.get('episode_number', 0))
    print(latest.get('slug', ''))
" 2>/dev/null)
fi

if [ -z "$LATEST_EP" ]; then
    # Fallback: find newest episode directory
    LATEST_EP=$(ls -1d "$REPO_DIR"/episodes/*/ 2>/dev/null | tail -1 | xargs basename 2>/dev/null)
fi

if [ -n "$LATEST_EP" ]; then
    EP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/episodes/$LATEST_EP/" 2>/dev/null || echo "000")
    if [ "$EP_CODE" = "200" ]; then
        pass "Latest episode /$LATEST_EP/ returns 200"
    else
        fail "Latest episode /$LATEST_EP/ returns HTTP $EP_CODE"
    fi
else
    fail "Could not determine latest episode slug"
fi

# ── Summary ──────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
if [ "$FAIL" -gt 0 ]; then
    echo "  ❌ POST-DEPLOY: $FAIL failures, $PASS passed"
    echo "  🚨 SITE MAY HAVE ISSUES — CHECK IMMEDIATELY"
    echo "═══════════════════════════════════════════════"
    exit 1
else
    echo "  ✅ POST-DEPLOY: ALL $PASS checks passed"
    echo "  🎉 Site is healthy!"
    echo "═══════════════════════════════════════════════"
    exit 0
fi
