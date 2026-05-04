#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== Scaffold Tests ==="
echo ""

# ── Directory existence ──
echo "Directory existence:"
for dir in \
  "skills/artist-patron" \
  "skills/artist-patron/scripts" \
  "skills/artist-patron/works" \
  "skills/artist-patron/tests" \
  "plugins/artist-patron/dashboard/dist"; do
  if [[ -d "$REPO_DIR/$dir" ]]; then
    echo "  ✓ $dir exists"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ $dir missing"
    FAILED=$((FAILED + 1))
  fi
done

# ── PERSPECTIVE.md has 5 section headers ──
echo ""
echo "PERSPECTIVE.md headers:"
HEADER_COUNT=$(grep -c '^## ' "$ARTIST_DIR/PERSPECTIVE.md" || true)
assert_eq "5" "$HEADER_COUNT" "PERSPECTIVE.md has 5 section headers"

# ── SKILL.md has valid YAML frontmatter ──
echo ""
echo "SKILL.md frontmatter:"
if head -n 1 "$ARTIST_DIR/SKILL.md" | grep -q '^---$'; then
  echo "  ✓ SKILL.md starts with ---"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ SKILL.md missing opening ---"
  FAILED=$((FAILED + 1))
fi

if head -n 2 "$ARTIST_DIR/SKILL.md" | tail -n 1 | grep -q 'name: artist-patron'; then
  echo "  ✓ SKILL.md frontmatter contains name: artist-patron"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ SKILL.md frontmatter missing name: artist-patron"
  FAILED=$((FAILED + 1))
fi

# ── SKILL.md section coverage ──
echo ""
echo "SKILL.md sections:"
SKILL="$ARTIST_DIR/SKILL.md"
for section in \
  "Context loading" \
  "Sensors" \
  "Actuators" \
  "Conversation routing" \
  "First session" \
  "Studio tools" \
  "Piece file layout" \
  "meta.json schema"; do
  if grep -q "$section" "$SKILL"; then
    echo "  ✓ contains '$section'"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ missing '$section'"
    FAILED=$((FAILED + 1))
  fi
done

HEADER_COUNT_SKILL=$(grep -c '## ' "$SKILL" || true)
if [[ "$HEADER_COUNT_SKILL" -ge 10 ]]; then
  echo "  ✓ SKILL.md has at least 10 headers ($HEADER_COUNT_SKILL)"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ SKILL.md has only $HEADER_COUNT_SKILL headers"
  FAILED=$((FAILED + 1))
fi

# ── studio.json parses ──
echo ""
echo "studio.json:"
assert_json_valid "$ARTIST_DIR/studio.json" "studio.json is valid JSON"

SCHEMA_VERSION=$(python3 -c "import json; print(json.load(open('$ARTIST_DIR/studio.json')).get('schema_version',''))")
assert_eq "1" "$SCHEMA_VERSION" "studio.json schema_version is '1'"

SETUP_COMPLETED=$(python3 -c "import json; v=json.load(open('$ARTIST_DIR/studio.json')).get('setup_completed'); print(type(v).__name__)")
assert_eq "bool" "$SETUP_COMPLETED" "studio.json setup_completed is a boolean"

# ── Test fixture well-formed ──
echo ""
echo "Test fixture:"
FIXTURE_DIR="$ARTIST_DIR/works/00000000-000000-0000-test-fixture"
for f in meta.json statement.md process.md output.png; do
  if [[ -f "$FIXTURE_DIR/$f" ]]; then
    echo "  ✓ $f exists"
    PASSED=$((PASSED + 1))
  else
    echo "  ✗ $f missing"
    FAILED=$((FAILED + 1))
  fi
done

assert_json_valid "$FIXTURE_DIR/meta.json" "fixture meta.json is valid JSON"

# ── helpers.sh sources without error ──
echo ""
echo "helpers.sh:"
assert_exit_code 0 "helpers.sh sources cleanly" bash -n "$ARTIST_DIR/scripts/helpers.sh"

# Check exports
if grep -q 'export -f write_atomic' "$ARTIST_DIR/scripts/helpers.sh"; then
  echo "  ✓ write_atomic exported"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ write_atomic not exported"
  FAILED=$((FAILED + 1))
fi

if grep 'export -f' "$ARTIST_DIR/scripts/helpers.sh" | grep -q 'validate_id'; then
  echo "  ✓ validate_id exported"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ validate_id not exported"
  FAILED=$((FAILED + 1))
fi

# ── validate-meta.sh accepts fixture ──
echo ""
echo "validate-meta.sh:"
assert_exit_code 0 "validate-meta.sh accepts fixture" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$FIXTURE_DIR/meta.json"

# ── setup.sh executable ──
echo ""
echo "setup.sh:"
if [[ -x "$REPO_DIR/setup.sh" ]]; then
  echo "  ✓ setup.sh is executable"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ setup.sh is not executable"
  FAILED=$((FAILED + 1))
fi

# ── Test setup_test_piece / teardown_test_pieces ──
echo ""
echo "Test harness functions:"
PIECE_DIR=$(setup_test_piece)
if [[ -f "$PIECE_DIR/meta.json" ]]; then
  echo "  ✓ setup_test_piece creates meta.json"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ setup_test_piece did not create meta.json"
  FAILED=$((FAILED + 1))
fi

# Verify the generated piece passes validation
assert_exit_code 0 "validate-meta.sh accepts generated test piece" bash "$ARTIST_DIR/scripts/validate-meta.sh" "$PIECE_DIR/meta.json"

teardown_test_pieces
if [[ ! -d "$PIECE_DIR" ]]; then
  echo "  ✓ teardown_test_pieces removes test pieces"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ teardown_test_pieces did not remove test pieces"
  FAILED=$((FAILED + 1))
fi

# ── Report ──
report_results
