#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== studio-check.sh Tests ==="
echo ""

CHECK_SCRIPT="$REPO_DIR/artist/scripts/studio-check.sh"
STUDIO_FILE="$ARTIST_DIR/studio.json"

# Backup studio.json
STUDIO_BACKUP="$ARTIST_DIR/.studio.json.backup"
cp "$STUDIO_FILE" "$STUDIO_BACKUP"

# ── Test 1: script runs without error ──
echo "Script runs without error:"
assert_exit_code 0 "studio-check runs" bash "$CHECK_SCRIPT"

# ── Test 2: studio.json updated with schema_version='1' ──
echo ""
echo "studio.json schema_version:"
SCHEMA_VERSION=$(python3 -c "import json; print(json.load(open('$STUDIO_FILE')).get('schema_version', ''))")
assert_eq "1" "$SCHEMA_VERSION" "schema_version is '1'"

# ── Test 3: python3 and curl are available ──
echo ""
echo "python3 and curl availability:"
TOOLS_AVAILABLE=$(python3 -c "import json; d=json.load(open('$STUDIO_FILE')); print(' '.join(d.get('tools_available', [])))")
if echo "$TOOLS_AVAILABLE" | grep -qw "python3"; then
  echo "  ✓ python3 is available"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ python3 is not available"
  FAILED=$((FAILED + 1))
fi

if echo "$TOOLS_AVAILABLE" | grep -qw "curl"; then
  echo "  ✓ curl is available"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ curl is not available"
  FAILED=$((FAILED + 1))
fi

# ── Test 4: model_family defaults to 'unknown' if no hermes config ──
echo ""
echo "model_family defaults to 'unknown' without hermes config:"
HERMES_CONFIG="$HOME/.hermes/config.yaml"
CONFIG_BACKUP=""
if [[ -f "$HERMES_CONFIG" ]]; then
  CONFIG_BACKUP="$HOME/.hermes/config.yaml.backup.$$"
  cp "$HERMES_CONFIG" "$CONFIG_BACKUP"
  rm -f "$HERMES_CONFIG"
fi

bash "$CHECK_SCRIPT" >/dev/null 2>&1
MODEL_FAMILY=$(python3 -c "import json; print(json.load(open('$STUDIO_FILE')).get('model_family', ''))")
assert_eq "unknown" "$MODEL_FAMILY" "model_family is 'unknown' without config"

# Restore config
if [[ -n "$CONFIG_BACKUP" && -f "$CONFIG_BACKUP" ]]; then
  mv "$CONFIG_BACKUP" "$HERMES_CONFIG"
fi

# ── Test 5: review_size defaults to 768 for unknown model ──
echo ""
echo "review_size defaults to 768 for unknown model:"
REVIEW_SIZE=$(python3 -c "import json; print(json.load(open('$STUDIO_FILE')).get('review_size', ''))")
assert_eq "768" "$REVIEW_SIZE" "review_size is 768 for unknown model"

# ── Test 6: envelope with --json contains available/missing ──
echo ""
echo "JSON envelope contains available/missing:"
ENVELOPE=$(bash "$CHECK_SCRIPT" --json)
SUCCESS=$(echo "$ENVELOPE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))')
assert_eq "True" "$SUCCESS" "envelope success is true"
HAS_AVAILABLE=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("available" in d.get("data", {}))')
assert_eq "True" "$HAS_AVAILABLE" "envelope data has 'available'"
HAS_MISSING=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("missing" in d.get("data", {}))')
assert_eq "True" "$HAS_MISSING" "envelope data has 'missing'"

# ── Restore studio.json ──
cp "$STUDIO_BACKUP" "$STUDIO_FILE"
rm -f "$STUDIO_BACKUP"

# ── Report ──
report_results
