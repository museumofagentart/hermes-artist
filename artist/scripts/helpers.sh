#!/usr/bin/env bash
# Shared helpers for artist skill scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKS_DIR="$ARTIST_DIR/works"

# ── Atomic writes ──
write_atomic() {
  local target="$1"
  local tmp="${target}.tmp.$$"
  cat > "$tmp" && mv "$tmp" "$target"
}

# ── ID validation ──
validate_id() {
  local id="$1"
  if [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]{4}-[a-z0-9-]{1,40}$ ]]; then
    return 0
  else
    return 1
  fi
}

# ── Envelope helpers ──
envelope_success() {
  local data="${1:-[]}"
  local meta="${2:-{}}"
  printf '{"success":true,"data":%s,"meta":%s}\n' "$data" "$meta"
}

envelope_error() {
  local msg="$1"
  printf '{"success":false,"error":"%s","meta":{"source":"artist"}}\n' "$msg"
}

# ── Exports ──
export -f write_atomic validate_id envelope_success envelope_error
export SCRIPT_DIR ARTIST_DIR WORKS_DIR
