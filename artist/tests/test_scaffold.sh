#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== Scaffold Tests ==="
echo ""

# ── Directory existence ──
echo "Directory existence:"
for dir in \
  "skills/artist" \
  "artist/scripts" \
  "artist/works" \
  "artist/tests" \
  "plugins/artist/dashboard/dist"; do
  if [[ -d "$REPO_DIR/$dir" ]]; then
    echo "  ✓ $dir exists"
    ((PASSED++))
  else
    echo "  ✗ $dir missing"
    ((FAILED++))
  fi
done

# ── PERSPECTIVE.md has 5 section headers ──
echo ""
echo "PERSPECTIVE.md headers:"
HEADER_COUNT=$(grep -c '^## ' "$REPO_DIR/artist/PERSPECTIVE.md" || true)
assert_eq "5" "$HEADER_COUNT" "PERSPECTIVE.md has 5 section headers"

# ── SKILL.md has valid YAML frontmatter ──
echo ""
echo "SKILL.md frontmatter:"
if head -n 1 "$REPO_DIR/skills/artist/SKILL.md" | grep -q '^---$'; then
  echo "  ✓ SKILL.md starts with ---"
  ((PASSED++))
else
  echo "  ✗ SKILL.md missing opening ---"
  ((FAILED++))
fi

if head -n 2 "$REPO_DIR/skills/artist/SKILL.md" | tail -n 1 | grep -q 'name: artist'; then
  echo "  ✓ SKILL.md frontmatter contains name: artist"
  ((PASSED++))
else
  echo "  ✗ SKILL.md frontmatter missing name: artist"
  ((FAILED++))
fi

# ── SKILL.md section coverage ──
echo ""
echo "SKILL.md sections:"
SKILL="$REPO_DIR/skills/artist/SKILL.md"
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
    ((PASSED++))
  else
    echo "  ✗ missing '$section'"
    ((FAILED++))
  fi
done

HEADER_COUNT_SKILL=$(grep -c '## ' "$SKILL" || true)
if [[ "$HEADER_COUNT_SKILL" -ge 10 ]]; then
  echo "  ✓ SKILL.md has at least 10 headers ($HEADER_COUNT_SKILL)"
  ((PASSED++))
else
  echo "  ✗ SKILL.md has only $HEADER_COUNT_SKILL headers"
  ((FAILED++))
fi

# ── studio.json parses ──
echo ""
echo "studio.json:"
assert_json_valid "$REPO_DIR/artist/studio.json" "studio.json is valid JSON"

SCHEMA_VERSION=$(python3 -c "import json; print(json.load(open('$REPO_DIR/artist/studio.json')).get('schema_version',''))")
assert_eq "1" "$SCHEMA_VERSION" "studio.json schema_version is '1'"

SETUP_COMPLETED=$(python3 -c "import json; print(json.load(open('$REPO_DIR/artist/studio.json')).get('setup_completed',''))")
assert_eq "False" "$SETUP_COMPLETED" "studio.json setup_completed is false"

# ── Test fixture well-formed ──
echo ""
echo "Test fixture:"
FIXTURE_DIR="$REPO_DIR/artist/works/00000000-000000-0000-test-fixture"
for f in meta.json statement.md process.md output.png; do
  if [[ -f "$FIXTURE_DIR/$f" ]]; then
    echo "  ✓ $f exists"
    ((PASSED++))
  else
    echo "  ✗ $f missing"
    ((FAILED++))
  fi
done

assert_json_valid "$FIXTURE_DIR/meta.json" "fixture meta.json is valid JSON"

# ── helpers.sh sources without error ──
echo ""
echo "helpers.sh:"
assert_exit_code 0 "helpers.sh sources cleanly" bash -n "$REPO_DIR/artist/scripts/helpers.sh"

# Check exports
if grep -q 'export -f write_atomic' "$REPO_DIR/artist/scripts/helpers.sh"; then
  echo "  ✓ write_atomic exported"
  ((PASSED++))
else
  echo "  ✗ write_atomic not exported"
  ((FAILED++))
fi

if grep 'export -f' "$REPO_DIR/artist/scripts/helpers.sh" | grep -q 'validate_id'; then
  echo "  ✓ validate_id exported"
  ((PASSED++))
else
  echo "  ✗ validate_id not exported"
  ((FAILED++))
fi

# ── validate-meta.sh accepts fixture ──
echo ""
echo "validate-meta.sh:"
assert_exit_code 0 "validate-meta.sh accepts fixture" bash "$REPO_DIR/artist/scripts/validate-meta.sh" "$FIXTURE_DIR/meta.json"

# ── install.sh executable ──
echo ""
echo "install.sh:"
if [[ -x "$REPO_DIR/install.sh" ]]; then
  echo "  ✓ install.sh is executable"
  ((PASSED++))
else
  echo "  ✗ install.sh is not executable"
  ((FAILED++))
fi

# ── Test setup_test_piece / teardown_test_pieces ──
echo ""
echo "Test harness functions:"
PIECE_DIR=$(setup_test_piece)
if [[ -f "$PIECE_DIR/meta.json" ]]; then
  echo "  ✓ setup_test_piece creates meta.json"
  ((PASSED++))
else
  echo "  ✗ setup_test_piece did not create meta.json"
  ((FAILED++))
fi

# Verify the generated piece passes validation
assert_exit_code 0 "validate-meta.sh accepts generated test piece" bash "$REPO_DIR/artist/scripts/validate-meta.sh" "$PIECE_DIR/meta.json"

teardown_test_pieces
if [[ ! -d "$PIECE_DIR" ]]; then
  echo "  ✓ teardown_test_pieces removes test pieces"
  ((PASSED++))
else
  echo "  ✗ teardown_test_pieces did not remove test pieces"
  ((FAILED++))
fi

# ── Report ──
report_results
