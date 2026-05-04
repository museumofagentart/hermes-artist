#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== feedback.sh Tests ==="
echo ""

FEEDBACK_SCRIPT="$ARTIST_DIR/scripts/feedback.sh"

# ── Setup test pieces ──
PIECE_DIR1=$(setup_test_piece "20260503-000000-0001-test-piece-fav")
PIECE_ID1=$(basename "$PIECE_DIR1")

PIECE_DIR2=$(setup_test_piece "20260503-000000-0002-test-piece-cmt")
PIECE_ID2=$(basename "$PIECE_DIR2")

# ── Test --set-favorite true sets flag + timestamp ──
echo "Set favorite true:"
OUTPUT=$(bash "$FEEDBACK_SCRIPT" "$PIECE_ID1" --set-favorite true --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for set-favorite true"
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["favorite"])')" "favorite is true"
FAVORITE_AT=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["favorite_at"])')
if [[ "$FAVORITE_AT" != "None" && -n "$FAVORITE_AT" ]]; then
  echo "  ✓ favorite_at is set"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ favorite_at is not set"
  FAILED=$((FAILED + 1))
fi
assert_exit_code 0 "validate-meta.sh passes after set-favorite true" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR1/meta.json"

# ── Test --set-favorite false clears flag ──
echo ""
echo "Set favorite false:"
OUTPUT=$(bash "$FEEDBACK_SCRIPT" "$PIECE_ID1" --set-favorite false --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for set-favorite false"
assert_eq "False" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["favorite"])')" "favorite is false"
assert_eq "None" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["favorite_at"])')" "favorite_at is null"
assert_exit_code 0 "validate-meta.sh passes after set-favorite false" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR1/meta.json"

# ── Test --set-favorite true twice is idempotent ──
echo ""
echo "Set favorite true twice (idempotent):"
bash "$FEEDBACK_SCRIPT" "$PIECE_ID1" --set-favorite true --json >/dev/null
OUTPUT=$(bash "$FEEDBACK_SCRIPT" "$PIECE_ID1" --set-favorite true --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true on second call"
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["favorite"])')" "favorite still true after second call"
COMMENTS_LEN=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["comments"]))')
assert_eq "0" "$COMMENTS_LEN" "no extra comments created by idempotent favorite"
assert_exit_code 0 "validate-meta.sh passes after idempotent favorite" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR1/meta.json"

# ── Test --set-discouraged true sets flag + timestamp ──
echo ""
echo "Set discouraged true:"
OUTPUT=$(bash "$FEEDBACK_SCRIPT" "$PIECE_ID1" --set-discouraged true --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for set-discouraged true"
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["discouraged"])')" "discouraged is true"
DISCOURAGED_AT=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["discouraged_at"])')
if [[ "$DISCOURAGED_AT" != "None" && -n "$DISCOURAGED_AT" ]]; then
  echo "  ✓ discouraged_at is set"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ discouraged_at is not set"
  FAILED=$((FAILED + 1))
fi
assert_exit_code 0 "validate-meta.sh passes after set-discouraged true" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR1/meta.json"

# ── Test --comment via stdin appends to comments array (run twice, verify 2 comments) ──
echo ""
echo "Comment via stdin:"
OUTPUT=$(printf 'First comment' | bash "$FEEDBACK_SCRIPT" "$PIECE_ID2" --comment --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for first comment"
COMMENTS_LEN=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["comments"]))')
assert_eq "1" "$COMMENTS_LEN" "comments array has 1 entry after first comment"

OUTPUT=$(printf 'Second comment' | bash "$FEEDBACK_SCRIPT" "$PIECE_ID2" --comment --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for second comment"
COMMENTS_LEN=$(echo "$OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["comments"]))')
assert_eq "2" "$COMMENTS_LEN" "comments array has 2 entries after second comment"

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; sys.exit(0 if d['comments'][0]['text'] == 'First comment' else 1)" 2>/dev/null; then
  echo "  ✓ first comment text preserved"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ first comment text not preserved"
  FAILED=$((FAILED + 1))
fi

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; sys.exit(0 if d['comments'][1]['text'] == 'Second comment' else 1)" 2>/dev/null; then
  echo "  ✓ second comment text preserved"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ second comment text not preserved"
  FAILED=$((FAILED + 1))
fi
assert_exit_code 0 "validate-meta.sh passes after comments" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR2/meta.json"

# ── Test comment with control char rejected ──
echo ""
echo "Comment with control char:"
OUTPUT=$(printf '\x01bad' | bash "$FEEDBACK_SCRIPT" "$PIECE_ID2" --comment --json || true)
assert_eq "False" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for control char in comment"

# ── Test comment over 2000 chars rejected ──
echo ""
echo "Comment over 2000 chars:"
LONG_COMMENT=$(python3 -c "print('x'*2001)")
OUTPUT=$(printf '%s' "$LONG_COMMENT" | bash "$FEEDBACK_SCRIPT" "$PIECE_ID2" --comment --json || true)
assert_eq "False" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for comment over 2000 chars"

# ── Test newlines and tabs in comment are allowed ──
echo ""
echo "Comment with newlines and tabs:"
OUTPUT=$(printf 'line1\nline2\tcol2' | bash "$FEEDBACK_SCRIPT" "$PIECE_ID2" --comment --json)
assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for comment with newlines and tabs"
if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; sys.exit(0 if d['comments'][-1]['text'] == 'line1\nline2\tcol2' else 1)" 2>/dev/null; then
  echo "  ✓ comment text preserves newlines and tabs"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ comment text does not preserve newlines and tabs"
  FAILED=$((FAILED + 1))
fi
assert_exit_code 0 "validate-meta.sh passes after newline/tab comment" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR2/meta.json"

# ── Test path traversal ID rejected ──
echo ""
echo "Path traversal ID:"
OUTPUT=$(bash "$FEEDBACK_SCRIPT" "../../etc/passwd" --set-favorite true --json || true)
assert_eq "False" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for path traversal ID"

# ── Verify original meta.json fields preserved after feedback mutation ──
echo ""
echo "Original fields preserved:"
META_TITLE=$(python3 -c "import json; print(json.load(open('$PIECE_DIR1/meta.json')).get('title',''))")
META_SEED=$(python3 -c "import json; print(json.load(open('$PIECE_DIR1/meta.json')).get('seed',''))")
META_MEDIUM=$(python3 -c "import json; print(json.load(open('$PIECE_DIR1/meta.json')).get('medium',''))")
assert_eq "Test Piece" "$META_TITLE" "title preserved"
assert_eq "test seed" "$META_SEED" "seed preserved"
assert_eq "image/png" "$META_MEDIUM" "medium preserved"

# ── Cleanup ──
teardown_test_pieces

# ── Report ──
report_results
