#!/usr/bin/env bash
# Generate a valid piece ID: YYYYMMDD-HHMMSS-MMMM-slug
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

if [[ $# -lt 1 ]]; then
  envelope_error "Usage: generate-id.sh <slug> [--json]"
  exit 1
fi

SLUG="$1"
JSON_OUT=false
if [[ "${2:-}" == "--json" ]]; then
  JSON_OUT=true
fi

# Validate slug: lowercase letters, digits, hyphens, 1-40 chars
if [[ ! "$SLUG" =~ ^[a-z0-9-]{1,40}$ ]]; then
  if $JSON_OUT; then
    envelope_error "Invalid slug: must be 1-40 chars of lowercase letters, digits, and hyphens"
  else
    echo "Error: Invalid slug: must be 1-40 chars of lowercase letters, digits, and hyphens" >&2
  fi
  exit 1
fi

# Generate timestamp and 4-digit sub-second component
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
SUBSEC=$(python3 -c "from datetime import datetime; print(f'{datetime.now().microsecond//100:04d}')")

ID="${TIMESTAMP}-${SUBSEC}-${SLUG}"

# Verify it passes internal validation
if ! validate_id "$ID"; then
  if $JSON_OUT; then
    envelope_error "Generated ID failed internal validation: $ID"
  else
    echo "Error: Generated ID failed internal validation: $ID" >&2
  fi
  exit 1
fi

if $JSON_OUT; then
  envelope_success "\"$ID\"" '{"source":"artist","generated":true}'
else
  echo "$ID"
fi
