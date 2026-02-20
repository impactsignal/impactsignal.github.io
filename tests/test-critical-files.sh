#!/bin/bash
# test-critical-files.sh — Pre-push validation for Impact Signals website
# Ensures critical files exist and are valid before any push to GitHub Pages.
# macOS bash 3.2 compatible. Exit non-zero on ANY failure.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }

echo "═══════════════════════════════════════════════"
echo "  Impact Signals — Pre-Push Validation"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. Critical files exist ──────────────────────
echo "📁 Checking critical files exist..."

CRITICAL_FILES="style.css index.html robots.txt sitemap.xml feed.xml CNAME episodes.json llms.txt llms-full.txt"
for f in $CRITICAL_FILES; do
    if [ -f "$REPO_DIR/$f" ]; then
        pass "$f exists"
    else
        fail "$f is MISSING"
    fi
done

# ── 2. style.css validation ─────────────────────
echo ""
echo "🎨 Validating style.css..."

if [ -f "$REPO_DIR/style.css" ]; then
    SIZE=$(wc -c < "$REPO_DIR/style.css" | tr -d ' ')
    if [ "$SIZE" -gt 1000 ]; then
        pass "style.css is $SIZE bytes (non-trivial)"
    else
        fail "style.css is only $SIZE bytes — likely truncated or empty"
    fi

    EXPECTED_SELECTORS="body .episode-list .featured-section .episode-page nav"
    for sel in $EXPECTED_SELECTORS; do
        if grep -q "$sel" "$REPO_DIR/style.css"; then
            pass "style.css contains '$sel'"
        else
            fail "style.css missing expected selector '$sel'"
        fi
    done
fi

# ── 3. index.html validation ────────────────────
echo ""
echo "📄 Validating index.html..."

if [ -f "$REPO_DIR/index.html" ]; then
    if grep -q 'style.css' "$REPO_DIR/index.html"; then
        pass "index.html references style.css"
    else
        fail "index.html does NOT reference style.css"
    fi

    if grep -q '<title>' "$REPO_DIR/index.html"; then
        pass "index.html has <title> tag"
    else
        fail "index.html missing <title> tag"
    fi

    if grep -q 'episode' "$REPO_DIR/index.html"; then
        pass "index.html contains episode content"
    else
        fail "index.html has no episode content"
    fi
fi

# ── 4. Episode directories ──────────────────────
echo ""
echo "📺 Checking episode directories..."

EPISODE_COUNT=0
EPISODE_MISSING=0
for ep_dir in "$REPO_DIR"/episodes/*/; do
    if [ -d "$ep_dir" ]; then
        EPISODE_COUNT=$((EPISODE_COUNT + 1))
        if [ ! -f "$ep_dir/index.html" ]; then
            fail "Episode dir $(basename "$ep_dir") missing index.html"
            EPISODE_MISSING=$((EPISODE_MISSING + 1))
        fi
    fi
done

if [ "$EPISODE_COUNT" -gt 0 ]; then
    VALID=$((EPISODE_COUNT - EPISODE_MISSING))
    pass "$VALID/$EPISODE_COUNT episode directories have index.html"
else
    fail "No episode directories found"
fi

# ── 5. feed.xml validation ──────────────────────
echo ""
echo "📡 Validating feed.xml..."

if [ -f "$REPO_DIR/feed.xml" ]; then
    # Check if xmllint is available
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$REPO_DIR/feed.xml" 2>/dev/null; then
            pass "feed.xml is valid XML"
        else
            fail "feed.xml is NOT valid XML"
        fi
    else
        # Fallback: check basic XML structure
        if grep -q '<?xml' "$REPO_DIR/feed.xml" && grep -q '</rss>' "$REPO_DIR/feed.xml"; then
            pass "feed.xml has valid XML structure (basic check)"
        else
            fail "feed.xml appears malformed"
        fi
    fi

    FEED_SIZE=$(wc -c < "$REPO_DIR/feed.xml" | tr -d ' ')
    if [ "$FEED_SIZE" -gt 500 ]; then
        pass "feed.xml is $FEED_SIZE bytes (non-trivial)"
    else
        fail "feed.xml is only $FEED_SIZE bytes — likely truncated"
    fi
fi

# ── 6. Check for deleted episode directories (git) ──
echo ""
echo "🔍 Checking for deleted episodes in git diff..."

if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    DELETED_EPISODES=$(git diff --cached --name-status 2>/dev/null | grep '^D' | grep 'episodes/' | grep 'index.html' || true)
    if [ -n "$DELETED_EPISODES" ]; then
        fail "Episode pages are being DELETED in this commit:"
        echo "$DELETED_EPISODES" | while read -r line; do
            echo "    🗑️  $line"
        done
    else
        pass "No episode pages being deleted"
    fi

    # Also check unstaged deletes of critical files
    DELETED_CRITICAL=$(git diff --name-status HEAD 2>/dev/null | grep '^D' || true)
    if [ -n "$DELETED_CRITICAL" ]; then
        for f in $CRITICAL_FILES; do
            if echo "$DELETED_CRITICAL" | grep -q "$f"; then
                fail "Critical file $f is being DELETED"
            fi
        done
    fi
fi

# ── 7. CNAME validation ─────────────────────────
echo ""
echo "🌐 Validating CNAME..."

if [ -f "$REPO_DIR/CNAME" ]; then
    DOMAIN=$(cat "$REPO_DIR/CNAME" | tr -d '[:space:]')
    if [ "$DOMAIN" = "impactsignals.ai" ]; then
        pass "CNAME points to impactsignals.ai"
    else
        fail "CNAME contains '$DOMAIN' instead of 'impactsignals.ai'"
    fi
fi

# ── Summary ──────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
if [ "$FAIL" -gt 0 ]; then
    echo "  ❌ FAILED: $FAIL failures, $PASS passed, $WARN warnings"
    echo "  🛑 Push should be BLOCKED"
    echo "═══════════════════════════════════════════════"
    exit 1
else
    echo "  ✅ ALL PASSED: $PASS checks passed, $WARN warnings"
    echo "═══════════════════════════════════════════════"
    exit 0
fi
