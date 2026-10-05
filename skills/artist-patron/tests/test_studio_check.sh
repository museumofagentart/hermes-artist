#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== studio-check.sh Tests ==="
echo ""

CHECK_SCRIPT="$ARTIST_DIR/scripts/studio-check.sh"
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
EMPTY_HERMES_HOME="$(mktemp -d)"
HERMES_HOME="$EMPTY_HERMES_HOME" bash "$CHECK_SCRIPT" >/dev/null 2>&1
MODEL_FAMILY=$(python3 -c "import json; print(json.load(open('$STUDIO_FILE')).get('model_family', ''))")
assert_eq "unknown" "$MODEL_FAMILY" "model_family is 'unknown' without config"

# ── Test 5: review_size defaults to 768 for unknown model ──
echo ""
echo "review_size defaults to 768 for unknown model:"
REVIEW_SIZE=$(python3 -c "import json; print(json.load(open('$STUDIO_FILE')).get('review_size', ''))")
assert_eq "768" "$REVIEW_SIZE" "review_size is 768 for unknown model"

# ── Test 6: envelope with --json contains available/missing ──
echo ""
echo "JSON envelope contains available/missing:"
ENVELOPE=$(HERMES_HOME="$EMPTY_HERMES_HOME" bash "$CHECK_SCRIPT" --json)
SUCCESS=$(echo "$ENVELOPE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))')
assert_eq "True" "$SUCCESS" "envelope success is true"
HAS_AVAILABLE=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("available" in d.get("data", {}))')
assert_eq "True" "$HAS_AVAILABLE" "envelope data has 'available'"
HAS_MISSING=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("missing" in d.get("data", {}))')
assert_eq "True" "$HAS_MISSING" "envelope data has 'missing'"

# ── Test 7: self-vision readiness (regression for hermes-da-kimi-6i6) ──
# The Kimi Coding Plan endpoint has no image input, so with
# auxiliary.vision.provider=auto hermes may hide vision_analyze and the agent
# falls back to browser_vision ("vision analyzing page [error]").
echo ""
echo "Self-vision readiness:"
FIXTURE_HOME="$(mktemp -d)"
self_vision() { python3 -c "import json; print(json.load(open('$STUDIO_FILE'))['self_vision']['$1'])"; }

cat > "$FIXTURE_HOME/config.yaml" <<'YAML'
model:
  default: kimi-k2.6
  provider: kimi-coding
auxiliary:
  vision:
    provider: auto
    model: ''
YAML
HUMAN_OUT=$(HERMES_HOME="$FIXTURE_HOME" bash "$CHECK_SCRIPT" 2>&1)
assert_eq "needs_config" "$(self_vision status)" "kimi-coding + auto vision => needs_config"
if self_vision fix | grep -q "auxiliary.vision"; then
  echo "  ✓ fix names auxiliary.vision"; PASSED=$((PASSED + 1))
else
  echo "  ✗ fix does not name auxiliary.vision"; FAILED=$((FAILED + 1))
fi
if echo "$HUMAN_OUT" | grep -q "vision_analyze"; then
  echo "  ✓ human output warns about vision_analyze"; PASSED=$((PASSED + 1))
else
  echo "  ✗ human output missing vision warning"; FAILED=$((FAILED + 1))
fi
ENV_SV=$(HERMES_HOME="$FIXTURE_HOME" bash "$CHECK_SCRIPT" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["self_vision"]["status"])')
assert_eq "needs_config" "$ENV_SV" "JSON envelope carries self_vision"

cat > "$FIXTURE_HOME/config.yaml" <<'YAML'
model:
  default: kimi-k2.6
  provider: kimi-coding
auxiliary:
  vision:
    provider: openrouter
    model: google/gemini-3-flash-preview
YAML
HERMES_HOME="$FIXTURE_HOME" bash "$CHECK_SCRIPT" >/dev/null 2>&1
assert_eq "configured" "$(self_vision status)" "explicit auxiliary.vision provider => configured"

cat > "$FIXTURE_HOME/config.yaml" <<'YAML'
model:
  default: gpt-5.5
  provider: openai-codex
auxiliary:
  vision:
    provider: auto
YAML
HERMES_HOME="$FIXTURE_HOME" bash "$CHECK_SCRIPT" >/dev/null 2>&1
assert_eq "auto" "$(self_vision status)" "vision-capable main provider + auto => auto"

HERMES_HOME="$EMPTY_HERMES_HOME" bash "$CHECK_SCRIPT" >/dev/null 2>&1
assert_eq "unknown" "$(self_vision status)" "no hermes config => unknown"
rm -rf "$FIXTURE_HOME" "$EMPTY_HERMES_HOME"

# ── Restore studio.json ──
cp "$STUDIO_BACKUP" "$STUDIO_FILE"
rm -f "$STUDIO_BACKUP"

# ── Report ──
report_results
