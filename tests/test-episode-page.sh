#!/bin/bash
# test-episode-page.sh <slug> — Verify a specific episode page
# macOS bash 3.2 compatible.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_URL="https://impactsignals.ai"
PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

if [ $# -lt 1 ]; then
    echo "Usage: $0 <episode-slug>"
    echo "Example: $0 7-wfp-grain-atms-google-75m-latam-gpt"
    exit 2
fi

SLUG="$1"
EP_URL="$SITE_URL/episodes/$SLUG/"

echo "═══════════════════════════════════════════════"
echo "  Episode Page Verification: $SLUG"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. HTTP status ───────────────────────────────
echo "🌐 Checking HTTP response..."

EP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$EP_URL" 2>/dev/null || echo "000")
if [ "$EP_CODE" = "200" ]; then
    pass "Episode page returns 200"
else
    fail "Episode page returns HTTP $EP_CODE"
fi

EP_BODY=$(curl -sL "$EP_URL" 2>/dev/null)

# ── 2. style.css reference ──────────────────────
echo ""
echo "🎨 Checking style.css link..."

if echo "$EP_BODY" | grep -q 'style.css'; then
    pass "Page references style.css"
else
    fail "Page does NOT reference style.css"
fi

# ── 3. HTML structure ────────────────────────────
echo ""
echo "📄 Checking HTML structure..."

if echo "$EP_BODY" | grep -q '<title>'; then
    pass "Has <title> tag"
else
    fail "Missing <title> tag"
fi

if echo "$EP_BODY" | grep -qi 'meta.*description'; then
    pass "Has meta description"
else
    fail "Missing meta description"
fi

if echo "$EP_BODY" | grep -qi 'meta.*og:title\|meta.*property="og:title"'; then
    pass "Has Open Graph title"
else
    fail "Missing Open Graph title"
fi

# Check for content sections
if echo "$EP_BODY" | grep -qi 'episode-page\|episode-content\|article'; then
    pass "Has episode content section"
else
    fail "Missing episode content section"
fi

# ── 4. YouTube embed (if applicable) ────────────
echo ""
echo "🎬 Checking YouTube embed..."

YOUTUBE_ID=""
if [ -f "$REPO_DIR/episodes.json" ]; then
    YOUTUBE_ID=$(python3 -c "
import json
with open('$REPO_DIR/episodes.json') as f:
    eps = json.load(f)
for ep in eps:
    if ep.get('slug') == '$SLUG':
        print(ep.get('youtube_id', ''))
        break
" 2>/dev/null)
fi

if [ -n "$YOUTUBE_ID" ]; then
    if echo "$EP_BODY" | grep -qi "youtube\|$YOUTUBE_ID"; then
        pass "YouTube embed present (ID: $YOUTUBE_ID)"
    else
        fail "YouTube embed MISSING (expected ID: $YOUTUBE_ID)"
    fi
else
    echo "  ℹ️  No youtube_id in episodes.json for this episode (skipping)"
fi

# ── 5. Local file check ─────────────────────────
echo ""
echo "📁 Checking local files..."

if [ -f "$REPO_DIR/episodes/$SLUG/index.html" ]; then
    pass "Local index.html exists"
    LOCAL_SIZE=$(wc -c < "$REPO_DIR/episodes/$SLUG/index.html" | tr -d ' ')
    if [ "$LOCAL_SIZE" -gt 500 ]; then
        pass "Local index.html is $LOCAL_SIZE bytes"
    else
        fail "Local index.html is only $LOCAL_SIZE bytes — likely incomplete"
    fi
else
    fail "Local episodes/$SLUG/index.html does NOT exist"
fi

# ── Summary ──────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
if [ "$FAIL" -gt 0 ]; then
    echo "  ❌ EPISODE CHECK: $FAIL failures, $PASS passed"
    echo "═══════════════════════════════════════════════"
    exit 1
else
    echo "  ✅ EPISODE CHECK: ALL $PASS checks passed"
    echo "═══════════════════════════════════════════════"
    exit 0
fi
