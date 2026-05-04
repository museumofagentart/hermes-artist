#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
source "$TEST_DIR/helpers.sh"

echo "=== studio-install.sh Tests ==="
echo ""

INSTALL_SCRIPT="$ARTIST_DIR/scripts/studio-install.sh"
STUDIO_FILE="$ARTIST_DIR/studio.json"

# Backup studio.json
STUDIO_BACKUP="$ARTIST_DIR/.studio.json.backup.$$"
cp "$STUDIO_FILE" "$STUDIO_BACKUP"

cleanup() {
  cp "$STUDIO_BACKUP" "$STUDIO_FILE"
  rm -f "$STUDIO_BACKUP"
}
trap cleanup EXIT

file_hash() {
  python3 -c "import hashlib; print(hashlib.md5(open('$1','rb').read()).hexdigest())"
}

write_studio() {
  printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); json.dump(d, open('$STUDIO_FILE', 'w'), indent=2)"
}

# ── Test 1: --dry-run outputs plan without executing ──
echo "Test --dry-run outputs plan without executing:"
write_studio '{"schema_version":"1","tools_missing":["pillow","ffmpeg","sox"],"tools_available":["python3","curl"],"setup_completed":true,"last_checked":"2024-01-01T00:00:00Z","tools":{},"review_size":768,"model_family":"unknown"}'
MD5_BEFORE=$(file_hash "$STUDIO_FILE")
OUTPUT=$(bash "$INSTALL_SCRIPT" --dry-run)
MD5_AFTER=$(file_hash "$STUDIO_FILE")
assert_eq "$MD5_BEFORE" "$MD5_AFTER" "studio.json unchanged during dry-run"
if echo "$OUTPUT" | grep -q "ffmpeg"; then
  echo "  ✓ plan contains ffmpeg"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ plan does not contain ffmpeg"
  FAILED=$((FAILED + 1))
fi
if echo "$OUTPUT" | grep -q "Pillow"; then
  echo "  ✓ plan contains Pillow"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ plan does not contain Pillow"
  FAILED=$((FAILED + 1))
fi
if echo "$OUTPUT" | grep -q "sox"; then
  echo "  ✓ plan contains sox"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ plan does not contain sox"
  FAILED=$((FAILED + 1))
fi

# ── Test 2: --dry-run --json returns envelope with install commands ──
echo ""
echo "Test --dry-run --json returns envelope with install commands:"
write_studio '{"schema_version":"1","tools_missing":["pillow","ffmpeg"],"tools_available":[],"setup_completed":true,"last_checked":"2024-01-01T00:00:00Z","tools":{},"review_size":768,"model_family":"unknown"}'
ENVELOPE=$(bash "$INSTALL_SCRIPT" --dry-run --json)
SUCCESS=$(echo "$ENVELOPE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))')
assert_eq "True" "$SUCCESS" "envelope success is true"
HAS_PLAN=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("plan" in d.get("data", {}))')
assert_eq "True" "$HAS_PLAN" "envelope data has 'plan'"
HAS_COMMANDS=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("commands" in d.get("data", {}))')
assert_eq "True" "$HAS_COMMANDS" "envelope data has 'commands'"
APT_CMD=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(any("apt-get" in c for c in d.get("data",{}).get("commands",[])))')
assert_eq "True" "$APT_CMD" "commands contain apt-get"
PIP_CMD=$(echo "$ENVELOPE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(any("pip install" in c for c in d.get("data",{}).get("commands",[])))')
assert_eq "True" "$PIP_CMD" "commands contain pip install"

# ── Test 3: no missing tools → 'nothing to install' message ──
echo ""
echo "Test no missing tools outputs 'nothing to install':"
write_studio '{"schema_version":"1","tools_missing":[],"tools_available":["python3","curl","ffmpeg"],"setup_completed":true,"last_checked":"2024-01-01T00:00:00Z","tools":{},"review_size":768,"model_family":"unknown"}'
OUTPUT=$(bash "$INSTALL_SCRIPT")
if echo "$OUTPUT" | grep -qi "nothing to install"; then
  echo "  ✓ outputs 'nothing to install'"
  PASSED=$((PASSED + 1))
else
  echo "  ✗ does not output 'nothing to install'"
  echo "    output: $OUTPUT"
  FAILED=$((FAILED + 1))
fi

JSON_OUTPUT=$(bash "$INSTALL_SCRIPT" --json)
SUCCESS=$(echo "$JSON_OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))')
assert_eq "True" "$SUCCESS" "JSON nothing-to-install envelope success is true"
INSTALLED_LEN=$(echo "$JSON_OUTPUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("data",{}).get("installed",[])))')
assert_eq "0" "$INSTALLED_LEN" "JSON installed list is empty"

# ── Report ──
report_results
