#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== review.sh Tests ==="
echo ""

REVIEW_SCRIPT="$ARTIST_DIR/scripts/review.sh"
STUDIO_FILE="$ARTIST_DIR/studio.json"

# Backup studio.json
STUDIO_BACKUP="$ARTIST_DIR/.studio.json.backup"
cp "$STUDIO_FILE" "$STUDIO_BACKUP"

# Temporarily move all non-test pieces so tests run against a clean works dir
FIXTURE_DIR="$WORKS_DIR/00000000-000000-0000-test-fixture"
FIXTURE_BACKUP="$WORKS_DIR/.00000000-000000-0000-test-fixture-backup"
if [[ -d "$FIXTURE_DIR" ]]; then
  mv "$FIXTURE_DIR" "$FIXTURE_BACKUP"
fi

# Backup any real pieces (not test pieces, not the fixture)
REAL_BACKUPS=()
for d in "$WORKS_DIR"/*; do
  if [[ -d "$d" ]]; then
    base=$(basename "$d")
    # Skip test pieces and hidden backups
    if [[ "$base" != *-test-piece* && "$base" != .* ]]; then
      backup="$WORKS_DIR/.$base-backup"
      mv "$d" "$backup"
      REAL_BACKUPS+=("$base")
    fi
  fi
done

# ── Helper to set model_family in studio.json ──
set_model_family() {
  local mf="$1"
  python3 -c "
import json
with open('$STUDIO_FILE', 'r') as f:
    data = json.load(f)
data['model_family'] = '$mf'
with open('$STUDIO_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
}

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

# Mark piece 2 as favorite
python3 -c "
import json
m = json.load(open('$PIECE_DIR2/meta.json'))
m['patron_feedback']['favorite'] = True
m['patron_feedback']['favorite_at'] = '2026-05-03T11:30:00.000000Z'
json.dump(m, open('$PIECE_DIR2/meta.json', 'w'), indent=2)
"

# Set default model_family
set_model_family "unknown"

# ── Test --last 2 returns at most 2 pieces ──
echo "--last 2 returns at most 2 pieces:"
OUTPUT=$(bash "$REVIEW_SCRIPT" --last 2 --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for --last 2"
assert_eq "2" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "--last 2 returns exactly 2 pieces"
assert_eq "$PIECE_ID1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "first piece is most recent"
assert_eq "$PIECE_ID2" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][1]["id"])')" "second piece is next most recent"

# ── Test --favorites returns only favorites ──
echo ""
echo "--favorites returns only favorites:"
OUTPUT=$(bash "$REVIEW_SCRIPT" --favorites --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for --favorites"
assert_eq "1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "--favorites returns 1 piece"
assert_eq "$PIECE_ID2" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "favorites returns correct piece"
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["favorite"])')" "returned piece has favorite=true"

# ── Test --id returns single piece ──
echo ""
echo "--id returns single piece:"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID3" --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for --id"
assert_eq "1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "--id returns exactly 1 piece"
assert_eq "$PIECE_ID3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "--id returns correct piece"
assert_eq "Gamma Piece" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["title"])')" "--id returns correct title"

# ── Test estimated_tokens varies by model_family ──
echo ""
echo "estimated_tokens varies by model_family:"

set_model_family "kimi-k2"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID1" --json)
assert_eq "756" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["estimated_tokens"])')" "kimi-k2 estimated_tokens is 756"

set_model_family "claude"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID1" --json)
assert_eq "900" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["estimated_tokens"])')" "claude estimated_tokens is 900"

set_model_family "gpt-4o"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID1" --json)
assert_eq "765" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["estimated_tokens"])')" "gpt-4o estimated_tokens is 765"

set_model_family "gemini"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID1" --json)
assert_eq "258" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["estimated_tokens"])')" "gemini estimated_tokens is 258"

set_model_family "unknown"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID1" --json)
assert_eq "0" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["estimated_tokens"])')" "unknown estimated_tokens is 0"

# ── Test missing review.jpg noted as missing ──
echo ""
echo "missing review.jpg noted as missing:"
# Test pieces don't have review.jpg by default
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID1" --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["review_image_missing"])')" "missing review.jpg flagged"
assert_eq "$PIECE_ID1" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')" "piece still listed when review.jpg missing"

# Create review.jpg for one piece and verify it's NOT flagged
printf '\x89PNG\r\n\x1a\n' > "$PIECE_DIR2/thumbs/review.jpg"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "$PIECE_ID2" --json)
HAS_MISSING=$(echo "$OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"][0]; print("review_image_missing" in d)')
assert_eq "False" "$HAS_MISSING" "existing review.jpg not flagged as missing"

# ── Test default behavior: last 5 + favorites ──
echo ""
echo "Default behavior (last 5 + favorites):"
# With 3 pieces and 1 favorite, default should return all 3 (last 5 covers all + favorite is already included)
OUTPUT=$(bash "$REVIEW_SCRIPT" --json)
assert_eq "3" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')" "default returns 3 pieces"

# ── Test envelope meta includes model_family and review_size ──
echo ""
echo "Envelope meta shape:"
OUTPUT=$(bash "$REVIEW_SCRIPT" --json)
assert_eq "artist" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["source"])')" "meta source is artist"
assert_eq "unknown" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["model_family"])')" "meta contains model_family"
assert_eq "768" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["review_size"])')" "meta contains review_size"

# ── Test human-readable output ──
echo ""
echo "Human-readable output:"
OUTPUT_HUMAN=$(bash "$REVIEW_SCRIPT" 2>/dev/null || true)
if echo "$OUTPUT_HUMAN" | grep -q "$PIECE_ID1"; then
  echo "  ✓ human-readable output contains piece ID"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ human-readable output missing piece ID"
  FAILED=$((FAILED + 1))
fi
if echo "$OUTPUT_HUMAN" | grep -q "MISSING"; then
  echo "  ✓ human-readable output notes missing images"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ human-readable output does not note missing images"
  FAILED=$((FAILED + 1))
fi

# ── Test invalid --id ──
echo ""
echo "Invalid --id:"
OUTPUT=$(bash "$REVIEW_SCRIPT" --id "bad-id" --json || true)
assert_eq "False" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "invalid id returns success=false"

# ── Teardown test pieces ──
teardown_test_pieces

# Restore real pieces
for base in "${REAL_BACKUPS[@]}"; do
  backup="$WORKS_DIR/.$base-backup"
  if [[ -d "$backup" ]]; then
    mv "$backup" "$WORKS_DIR/$base"
  fi
done

# Restore fixture piece
if [[ -d "$FIXTURE_BACKUP" ]]; then
  mv "$FIXTURE_BACKUP" "$FIXTURE_DIR"
fi

# Restore studio.json
mv "$STUDIO_BACKUP" "$STUDIO_FILE"

# ── Report ──
report_results
