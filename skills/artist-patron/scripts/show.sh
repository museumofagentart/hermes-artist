#!/usr/bin/env bash
# Usage: show.sh <id> [--json]
# Full piece data: meta + statement + output path + thumbnail path + review image path.
# If --json omitted and chafa available, renders a terminal preview.
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
      if $JSON_OUT; then
        :
      else
        envelope_error "Unknown flag: $arg"
        exit 1
      fi
      ;;
    *)
      if [[ -z "$PIECE_ID" ]]; then
        PIECE_ID="$arg"
      fi
      ;;
  esac
done

if [[ -z "$PIECE_ID" ]]; then
  envelope_error "Usage: show.sh <id> [--json]"
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

if [[ ! -f "$STATEMENT_FILE" ]]; then
  envelope_error "Statement not found for piece: $PIECE_ID"
  exit 1
fi

# ── Read data ──
STATEMENT="$(cat "$STATEMENT_FILE")"
OUTPUT_FILE="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('output_file',''))")"
MEDIUM="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('medium',''))")"

OUTPUT_PATH="$PIECE_DIR/$OUTPUT_FILE"
THUMB_PATH="$PIECE_DIR/thumbs/thumb.jpg"
REVIEW_PATH="$PIECE_DIR/thumbs/review.jpg"

# ── Build JSON data object ──
JSON_DATA="$(python3 -c "
import json, sys
meta = json.load(open('$META_FILE'))
meta['statement'] = open('$STATEMENT_FILE').read()
meta['output_path'] = '$OUTPUT_PATH'
meta['thumbnail_path'] = '$THUMB_PATH'
meta['review_image_path'] = '$REVIEW_PATH'
print(json.dumps(meta))
")"

if $JSON_OUT; then
  envelope_success "$JSON_DATA" '{"source":"artist-patron","piece_id":"'$PIECE_ID'"}'
  exit 0
fi

# ── Human-readable output ──
TITLE="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('title',''))")"
CREATED_AT="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('created_at',''))")"
SEED="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('seed',''))")"
TOOLS_USED="$(python3 -c "import json; print(', '.join(json.load(open('$META_FILE')).get('tools_used',[])))")"

printf '━━━ %s ━━━\n' "$TITLE"
printf 'ID:       %s\n' "$PIECE_ID"
printf 'Created:  %s\n' "$CREATED_AT"
printf 'Medium:   %s\n' "$MEDIUM"
printf 'Seed:     %s\n' "$SEED"
printf 'Tools:    %s\n' "$TOOLS_USED"
printf 'Output:   %s\n' "$OUTPUT_PATH"
printf 'Thumb:    %s\n' "$THUMB_PATH"
printf 'Review:   %s\n' "$REVIEW_PATH"
printf '\n━━━ Statement ━━━\n%s\n' "$STATEMENT"

# ── Terminal preview via chafa ──
if command -v chafa >/dev/null 2>&1 && [[ -f "$OUTPUT_PATH" ]]; then
  printf '\n━━━ Preview ━━━\n'
  case "$MEDIUM" in
    image/*)
      chafa "$OUTPUT_PATH" 2>/dev/null || true
      ;;
    *)
      printf '(chafa preview only available for image media)\n'
      ;;
  esac
fi
