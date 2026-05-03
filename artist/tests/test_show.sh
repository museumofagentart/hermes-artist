#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== show.sh Tests ==="
echo ""

SHOW_SCRIPT="$REPO_DIR/artist/scripts/show.sh"
FIXTURE_ID="00000000-000000-0000-test-fixture"
FIXTURE_DIR="$REPO_DIR/artist/works/$FIXTURE_ID"

# ── Test fixture piece returns valid envelope with correct fields ──
echo "Valid piece envelope:"
OUTPUT=$(bash "$SHOW_SCRIPT" "$FIXTURE_ID" --json)

assert_eq "True" "$(echo "$OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is true for fixture"
assert_json_valid "$FIXTURE_DIR/meta.json" "fixture meta.json is valid JSON"

# Verify all meta.json schema fields appear in output
for field in id title created_at seed medium output_file tools_used revision_of references patron_feedback; do
  if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; sys.exit(0 if '$field' in d else 1)" 2>/dev/null; then
    echo "  ✓ output contains field: $field"
    ((PASSED++))
  else
    echo "  ✗ output missing field: $field"
    ((FAILED++))
  fi
done

# Verify statement text is present
if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; sys.exit(0 if 'statement' in d and len(d['statement']) > 0 else 1)" 2>/dev/null; then
  echo "  ✓ output contains statement"
  ((PASSED++))
else
  echo "  ✗ output missing statement"
  ((FAILED++))
fi

# Verify paths are present
for path_field in output_path thumbnail_path review_image_path; do
  if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; sys.exit(0 if '$path_field' in d and len(d['$path_field']) > 0 else 1)" 2>/dev/null; then
    echo "  ✓ output contains path: $path_field"
    ((PASSED++))
  else
    echo "  ✗ output missing path: $path_field"
    ((FAILED++))
  fi
done

# ── Non-existent ID returns error envelope ──
echo ""
echo "Non-existent piece:"
OUTPUT_MISSING=$(bash "$SHOW_SCRIPT" "99999999-999999-9999-non-existent" --json || true)
assert_eq "False" "$(echo "$OUTPUT_MISSING" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for missing piece"

# ── Path traversal ID rejected ──
echo ""
echo "Path traversal ID:"
OUTPUT_TRAVERSAL=$(bash "$SHOW_SCRIPT" "../../etc/passwd" --json || true)
assert_eq "False" "$(echo "$OUTPUT_TRAVERSAL" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for path traversal"

# ── Control chars in ID rejected ──
echo ""
echo "Control characters in ID:"
# Use printf to embed a control character
CTRL_ID=$(printf '20260502-143200-7382-test\x01-piece')
OUTPUT_CTRL=$(bash "$SHOW_SCRIPT" "$CTRL_ID" --json || true)
assert_eq "False" "$(echo "$OUTPUT_CTRL" | python3 -c 'import json,sys; print(json.load(sys.stdin)["success"])')" "success is false for control chars in ID"

# ── Test human-readable output (no --json) ──
echo ""
echo "Human-readable output:"
OUTPUT_HUMAN=$(bash "$SHOW_SCRIPT" "$FIXTURE_ID" 2>/dev/null || true)
if echo "$OUTPUT_HUMAN" | grep -q "Test Fixture Piece"; then
  echo "  ✓ human-readable output contains title"
  ((PASSED++))
else
  echo "  ✗ human-readable output missing title"
  ((FAILED++))
fi

if echo "$OUTPUT_HUMAN" | grep -q "Statement"; then
  echo "  ✓ human-readable output contains 'Statement' header"
  ((PASSED++))
else
  echo "  ✗ human-readable output missing 'Statement' header"
  ((FAILED++))
fi

# ── Report ──
report_results
