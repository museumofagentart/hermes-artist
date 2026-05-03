#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
source "$TEST_DIR/helpers.sh"

GEN_ID="$REPO_DIR/artist/scripts/generate-id.sh"

echo "=== generate-id.sh Tests ==="
echo ""

# ── Basic generation ──
echo "Basic generation:"
ID=$(bash "$GEN_ID" "test-piece")
if [[ "$ID" =~ ^[0-9]{8}-[0-9]{6}-[0-9]{4}-test-piece$ ]]; then
  echo "  ✓ ID matches expected format: $ID"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ ID does not match expected format: $ID"
  FAILED=$((FAILED + 1))
fi

# ── With hyphens in slug ──
echo ""
echo "Hyphenated slug:"
ID=$(bash "$GEN_ID" "self-portrait")
if [[ "$ID" =~ ^[0-9]{8}-[0-9]{6}-[0-9]{4}-self-portrait$ ]]; then
  echo "  ✓ hyphenated slug works: $ID"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ hyphenated slug failed: $ID"
  FAILED=$((FAILED + 1))
fi

# ── JSON output ──
echo ""
echo "JSON output:"
JSON=$(bash "$GEN_ID" "json-test" --json)
if [[ "$JSON" == *'"success":true'* && "$JSON" == *'"generated":true'* ]]; then
  echo "  ✓ JSON envelope is success"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ JSON envelope malformed: $JSON"
  FAILED=$((FAILED + 1))
fi

EXTRACTED_ID=$(python3 -c "import json,sys; print(json.load(sys.stdin)['data'])" <<< "$JSON")
if [[ "$EXTRACTED_ID" =~ ^[0-9]{8}-[0-9]{6}-[0-9]{4}-json-test$ ]]; then
  echo "  ✓ JSON data contains valid ID: $EXTRACTED_ID"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ JSON data invalid: $EXTRACTED_ID"
  FAILED=$((FAILED + 1))
fi

# ── Invalid slug: uppercase ──
echo ""
echo "Invalid slug rejection:"
assert_exit_code 1 "rejects uppercase slug" bash "$GEN_ID" "BadSlug"

# ── Invalid slug: too long ──
assert_exit_code 1 "rejects 41-char slug" bash "$GEN_ID" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# ── Invalid slug: spaces ──
assert_exit_code 1 "rejects slug with spaces" bash "$GEN_ID" "bad slug"

# ── Invalid slug: special chars ──
assert_exit_code 1 "rejects slug with underscore" bash "$GEN_ID" "bad_slug"

# ── Empty slug ──
assert_exit_code 1 "rejects empty slug" bash "$GEN_ID" ""

# ── Uniqueness: generate two IDs in quick succession ──
echo ""
echo "Uniqueness:"
ID1=$(bash "$GEN_ID" "unique-test")
ID2=$(bash "$GEN_ID" "unique-test")
if [[ "$ID1" != "$ID2" ]]; then
  echo "  ✓ two rapid IDs differ"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ two rapid IDs are identical: $ID1"
  FAILED=$((FAILED + 1))
fi

# ── Report ──
report_results
