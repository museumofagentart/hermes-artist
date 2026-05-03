#!/usr/bin/env bash
# Validate meta.json against required fields and types
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

if [[ $# -lt 1 ]]; then
  envelope_error "Usage: validate-meta.sh <path-to-meta.json> [--json]"
  exit 1
fi

META_FILE="$1"
JSON_OUT=false
if [[ "${2:-}" == "--json" ]]; then
  JSON_OUT=true
fi

if [[ ! -f "$META_FILE" ]]; then
  if $JSON_OUT; then
    envelope_error "meta.json not found: $META_FILE"
  else
    echo "Error: meta.json not found: $META_FILE"
  fi
  exit 1
fi

ERRORS=""

# Check required top-level fields
REQUIRED_FIELDS=("schema_version" "id" "title" "created_at" "seed" "medium" "output_file" "tools_used" "revision_of" "references" "patron_feedback")
for field in "${REQUIRED_FIELDS[@]}"; do
  if ! python3 -c "
import json, sys
data = json.load(open('$META_FILE'))
if '$field' not in data:
    sys.exit(1)
" 2>/dev/null; then
    ERRORS="${ERRORS}Missing required field: $field. "
  fi
done

# Check patron_feedback sub-fields
if ! python3 -c "
import json, sys
data = json.load(open('$META_FILE'))
pf = data.get('patron_feedback', {})
required_pf = ['favorite', 'favorite_at', 'discouraged', 'discouraged_at', 'comments']
for f in required_pf:
    if f not in pf:
        sys.exit(1)
" 2>/dev/null; then
  ERRORS="${ERRORS}Missing patron_feedback sub-fields. "
fi

# Check id format
if ! python3 -c "
import json, re, sys
data = json.load(open('$META_FILE'))
id_val = data.get('id', '')
if not re.match(r'^[0-9]{8}-[0-9]{6}-[0-9]{4}-[a-z0-9-]{1,40}$', id_val):
    sys.exit(1)
" 2>/dev/null; then
  ERRORS="${ERRORS}Invalid id format. "
fi

# Check schema_version
if ! python3 -c "
import json, sys
data = json.load(open('$META_FILE'))
if data.get('schema_version') != '1':
    sys.exit(1)
" 2>/dev/null; then
  ERRORS="${ERRORS}schema_version must be '1'. "
fi

if [[ -n "$ERRORS" ]]; then
  if $JSON_OUT; then
    envelope_error "Validation failed: $ERRORS"
  else
    echo "Validation failed: $ERRORS"
  fi
  exit 1
fi

if $JSON_OUT; then
  envelope_success "\"$META_FILE\"" '{"source":"artist","validated":true}'
else
  echo "OK: $META_FILE"
fi
