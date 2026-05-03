#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== share.sh Tests ==="
echo ""

SHARE_SCRIPT="$REPO_DIR/artist/scripts/share.sh"
FIXTURE_ID="00000000-000000-0000-test-fixture"
FIXTURE_DIR="$REPO_DIR/artist/works/$FIXTURE_ID"

# ── Valid piece returns Twitter intent URL ──
echo "Valid piece URL:"
OUTPUT=$(bash "$SHARE_SCRIPT" "$FIXTURE_ID" --json)

assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for fixture"

URL=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["url"])')
OUTPUT_PATH=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["output_path"])')

# URL starts with correct prefix
if [[ "$URL" == https://twitter.com/intent/tweet?text=* ]]; then
  echo "  ✓ URL is valid Twitter intent URL"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ URL is not a valid Twitter intent URL"
  echo "    actual: $URL"
  FAILED=$((FAILED + 1))
fi

# ── URL contains @agentartmuseum ──
echo ""
echo "URL contains @agentartmuseum:"
DECODED_TEXT="$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$URL'.split('?text=')[1]))")"
if echo "$DECODED_TEXT" | grep -q '@agentartmuseum'; then
  echo "  ✓ decoded text contains @agentartmuseum"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ decoded text missing @agentartmuseum"
  echo "    decoded: $DECODED_TEXT"
  FAILED=$((FAILED + 1))
fi

# ── URL is properly percent-encoded ──
echo ""
echo "URL percent-encoding:"
# The URL should contain percent-encoded characters for spaces and special chars
if echo "$URL" | grep -q '%20\|%2C\|%40'; then
  echo "  ✓ URL contains percent-encoded characters"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ URL missing percent-encoded characters"
  echo "    actual: $URL"
  FAILED=$((FAILED + 1))
fi

# ── Output path is present ──
echo ""
echo "Output path in envelope:"
if [[ -n "$OUTPUT_PATH" ]] && [[ "$OUTPUT_PATH" == *"$FIXTURE_ID"* ]]; then
  echo "  ✓ output_path contains piece ID"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ output_path missing or invalid"
  echo "    actual: $OUTPUT_PATH"
  FAILED=$((FAILED + 1))
fi

# ── Missing statement.md falls back to title ──
echo ""
echo "Missing statement.md fallback:"
# Create a test piece without statement.md
PIECE_DIR=$(setup_test_piece "20260503-000000-0001-test-share-fallback")
PIECE_ID=$(basename "$PIECE_DIR")
python3 -c "
import json
m = json.load(open('$PIECE_DIR/meta.json'))
m['title'] = 'Fallback Title Piece'
json.dump(m, open('$PIECE_DIR/meta.json', 'w'), indent=2)
"
# Ensure no statement.md exists
rm -f "$PIECE_DIR/statement.md"

OUTPUT_FALLBACK=$(bash "$SHARE_SCRIPT" "$PIECE_ID" --json)
URL_FALLBACK=$(echo "$OUTPUT_FALLBACK" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["url"])')
DECODED_FALLBACK="$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$URL_FALLBACK'.split('?text=')[1]))")"

if echo "$DECODED_FALLBACK" | grep -q 'Fallback Title Piece'; then
  echo "  ✓ fallback uses piece title"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ fallback did not use piece title"
  echo "    decoded: $DECODED_FALLBACK"
  FAILED=$((FAILED + 1))
fi

# ── Invalid ID returns error envelope ──
echo ""
echo "Invalid piece ID:"
OUTPUT_INVALID=$(bash "$SHARE_SCRIPT" "not-a-valid-id" --json || true)
assert_eq "False" "$(echo "$OUTPUT_INVALID" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for invalid ID"

# ── Non-existent ID returns error envelope ──
echo ""
echo "Non-existent piece:"
OUTPUT_MISSING=$(bash "$SHARE_SCRIPT" "99999999-999999-9999-non-existent" --json || true)
assert_eq "False" "$(echo "$OUTPUT_MISSING" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for missing piece"

# ── Human-readable output ──
echo ""
echo "Human-readable output:"
OUTPUT_HUMAN=$(bash "$SHARE_SCRIPT" "$FIXTURE_ID" 2>/dev/null || true)
if echo "$OUTPUT_HUMAN" | grep -q 'twitter.com/intent/tweet'; then
  echo "  ✓ human-readable output contains Twitter URL"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ human-readable output missing Twitter URL"
  FAILED=$((FAILED + 1))
fi

# ── Teardown ──
teardown_test_pieces

# ── Report ──
report_results
