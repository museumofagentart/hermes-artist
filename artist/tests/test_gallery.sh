#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== gallery.sh Tests ==="
echo ""

GALLERY_SCRIPT="$REPO_DIR/artist/scripts/gallery.sh"

# Temporarily move fixture piece so tests run against a clean works dir
FIXTURE_DIR="$WORKS_DIR/00000000-000000-0000-test-fixture"
FIXTURE_BACKUP="$WORKS_DIR/.00000000-000000-0000-test-fixture-backup"
if [[ -d "$FIXTURE_DIR" ]]; then
  mv "$FIXTURE_DIR" "$FIXTURE_BACKUP"
fi

# ── Empty gallery ──
echo "Empty gallery:"
OUTPUT=$(bash "$GALLERY_SCRIPT" --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for empty gallery"
assert_eq "0" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "data is empty for empty gallery"
assert_eq "0" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["total"])')" "total is 0 for empty gallery"

# ── Setup test pieces ──
PIECE_DIR1=$(setup_test_piece "20260503-000000-0001-test-piece-a")
PIECE_ID1=$(basename "$PIECE_DIR1")
python3 -c "
import json
m = json.load(open('$PIECE_DIR1/meta.json'))
m['created_at'] = '2026-05-03T12:00:00.000000Z'
m['title'] = 'Alpha Piece'
json.dump(m, open('$PIECE_DIR1/meta.json', 'w'), indent=2)
"

PIECE_DIR2=$(setup_test_piece "20260503-000000-0002-test-piece-b")
PIECE_ID2=$(basename "$PIECE_DIR2")
python3 -c "
import json
m = json.load(open('$PIECE_DIR2/meta.json'))
m['created_at'] = '2026-05-03T11:00:00.000000Z'
m['title'] = 'Beta Piece'
json.dump(m, open('$PIECE_DIR2/meta.json', 'w'), indent=2)
"

PIECE_DIR3=$(setup_test_piece "20260503-000000-0003-test-piece-c")
PIECE_ID3=$(basename "$PIECE_DIR3")
python3 -c "
import json
m = json.load(open('$PIECE_DIR3/meta.json'))
m['created_at'] = '2026-05-03T10:00:00.000000Z'
m['title'] = 'Gamma Piece'
json.dump(m, open('$PIECE_DIR3/meta.json', 'w'), indent=2)
"

# ── Populated gallery ──
echo ""
echo "Populated gallery:"
OUTPUT=$(bash "$GALLERY_SCRIPT" --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for populated gallery"
assert_eq "3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["total"])')" "total is 3 for populated gallery"
assert_eq "3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "data has 3 pieces"

# Verify sort order (created_at descending: Alpha, Beta, Gamma)
FIRST_ID=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
SECOND_ID=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][1]["id"])')
THIRD_ID=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][2]["id"])')
assert_eq "$PIECE_ID1" "$FIRST_ID" "first piece is Alpha (most recent)"
assert_eq "$PIECE_ID2" "$SECOND_ID" "second piece is Beta"
assert_eq "$PIECE_ID3" "$THIRD_ID" "third piece is Gamma (oldest)"

# ── Pagination: limit 1 offset 0 ──
echo ""
echo "Pagination limit=1 offset=0:"
OUTPUT=$(bash "$GALLERY_SCRIPT" --limit 1 --offset 0 --json)
assert_eq "1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "limit 1 returns 1 piece"
assert_eq "$PIECE_ID1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "limit 1 offset 0 returns first piece"
assert_eq "3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["total"])')" "total remains 3 with pagination"
assert_eq "0" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["offset"])')" "offset is 0"
assert_eq "1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["limit"])')" "limit is 1"

# ── Pagination: limit 1 offset 2 ──
echo ""
echo "Pagination limit=1 offset=2:"
OUTPUT=$(bash "$GALLERY_SCRIPT" --limit 1 --offset 2 --json)
assert_eq "1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "limit 1 offset 2 returns 1 piece"
assert_eq "$PIECE_ID3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "limit 1 offset 2 returns third piece"

# ── Favorites filter ──
echo ""
echo "Favorites filter:"
# Mark piece 2 as favorite
python3 -c "
import json
m = json.load(open('$PIECE_DIR2/meta.json'))
m['patron_feedback']['favorite'] = True
m['patron_feedback']['favorite_at'] = '2026-05-03T11:30:00.000000Z'
json.dump(m, open('$PIECE_DIR2/meta.json', 'w'), indent=2)
"

OUTPUT=$(bash "$GALLERY_SCRIPT" --favorites --json)
assert_eq "1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "favorites returns 1 piece"
assert_eq "$PIECE_ID2" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "favorites returns correct piece"
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["patron_feedback"]["favorite"])')" "returned piece has favorite=true"

# ── Envelope shape ──
echo ""
echo "Envelope shape:"
OUTPUT=$(bash "$GALLERY_SCRIPT" --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "envelope has success key"

# Verify data is array
DATA_TYPE=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(type(json.load(sys.stdin)["data"]).__name__)')
assert_eq "list" "$DATA_TYPE" "envelope data is a list"

# Verify meta keys
for key in source total offset limit; do
  if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['meta']; sys.exit(0 if '$key' in d else 1)" 2>/dev/null; then
    echo "  ✓ meta contains key: $key"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ meta missing key: $key"
    FAILED=$((FAILED + 1))
  fi
done
assert_eq "artist" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["source"])')" "meta source is artist"

# ── Human-readable output ──
echo ""
echo "Human-readable output:"
OUTPUT_HUMAN=$(bash "$GALLERY_SCRIPT" 2>/dev/null || true)
if echo "$OUTPUT_HUMAN" | grep -q "Alpha Piece"; then
  echo "  ✓ human-readable output contains title"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ human-readable output missing title"
  FAILED=$((FAILED + 1))
fi
if echo "$OUTPUT_HUMAN" | grep -q "$PIECE_ID1"; then
  echo "  ✓ human-readable output contains piece ID"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ human-readable output missing piece ID"
  FAILED=$((FAILED + 1))
fi

# ── Malformed meta.json skipped ──
echo ""
echo "Malformed meta.json:"
# Create a piece dir with malformed meta.json
BAD_DIR="$WORKS_DIR/20260503-000000-9999-test-piece-bad"
mkdir -p "$BAD_DIR"
echo "not valid json {{{" > "$BAD_DIR/meta.json"

OUTPUT=$(bash "$GALLERY_SCRIPT" --json 2>/dev/null)
assert_eq "3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["total"])')" "malformed piece skipped, total still 3"
assert_eq "3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "malformed piece skipped, data still has 3"

# Clean up bad dir
rm -rf "$BAD_DIR"

# ── Teardown test pieces ──
teardown_test_pieces

# Restore fixture piece
if [[ -d "$FIXTURE_BACKUP" ]]; then
  mv "$FIXTURE_BACKUP" "$FIXTURE_DIR"
fi

# ── Report ──
report_results
