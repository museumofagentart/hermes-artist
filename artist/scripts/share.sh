#!/usr/bin/env bash
# Usage: share.sh <id> [--json]
# Generates Twitter compose URL with statement excerpt + @agentartmuseum.
# Opens browser if xdg-open/open available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# ── Parse args ──
JSON_OUT=false
PIECE_ID=""

for arg in "$@"; do
  case "$arg" in
    --json)
      JSON_OUT=true
      ;;
    -*)
      envelope_error "Unknown flag: $arg"
      exit 1
      ;;
    *)
      if [[ -z "$PIECE_ID" ]]; then
        PIECE_ID="$arg"
      fi
      ;;
  esac
done

if [[ -z "$PIECE_ID" ]]; then
  envelope_error "Usage: share.sh <id> [--json]"
  exit 1
fi

# ── Validate ID ──
if ! validate_id "$PIECE_ID"; then
  envelope_error "Invalid piece ID format: $PIECE_ID"
  exit 1
fi

# ── Reject path traversal ──
if [[ "$PIECE_ID" == *..* ]] || [[ "$PIECE_ID" == */* ]]; then
  envelope_error "Invalid piece ID: path traversal detected"
  exit 1
fi

# ── Reject control characters ──
if [[ "$PIECE_ID" =~ [[:cntrl:]] ]]; then
  envelope_error "Invalid piece ID: control characters detected"
  exit 1
fi

PIECE_DIR="$WORKS_DIR/$PIECE_ID"
META_FILE="$PIECE_DIR/meta.json"
STATEMENT_FILE="$PIECE_DIR/statement.md"

if [[ ! -d "$PIECE_DIR" ]] || [[ ! -f "$META_FILE" ]]; then
  envelope_error "Piece not found: $PIECE_ID"
  exit 1
fi

# ── Read statement or fall back to title ──
if [[ -f "$STATEMENT_FILE" ]]; then
  STATEMENT="$(cat "$STATEMENT_FILE")"
else
  STATEMENT="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('title',''))")"
fi

# ── Truncate to ~200 chars ──
# Remove markdown heading syntax for cleaner share text
STATEMENT="$(echo "$STATEMENT" | sed 's/^#* //')"
if [[ ${#STATEMENT} -gt 200 ]]; then
  STATEMENT="${STATEMENT:0:200}…"
fi

# ── Append @agentartmuseum ──
SHARE_TEXT="${STATEMENT} @agentartmuseum"

# ── URL-encode ──
ENCODED_TEXT="$(printf '%s' "$SHARE_TEXT" | python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))')"
TWITTER_URL="https://twitter.com/intent/tweet?text=${ENCODED_TEXT}"

# ── Get output file path ──
OUTPUT_FILE="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('output_file',''))")"
OUTPUT_PATH="$PIECE_DIR/$OUTPUT_FILE"

# ── Open browser if available ──
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$TWITTER_URL" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then
  open "$TWITTER_URL" >/dev/null 2>&1 || true
fi

# ── Output ──
if $JSON_OUT; then
  envelope_success "{\"url\":\"$TWITTER_URL\",\"output_path\":\"$OUTPUT_PATH\"}" "{\"source\":\"artist\",\"piece_id\":\"$PIECE_ID\"}"
else
  printf '%s\n' "$TWITTER_URL"
fi
