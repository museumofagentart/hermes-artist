#!/usr/bin/env bash
# Usage: feedback.sh <id> [--set-favorite true|false] [--set-discouraged true|false] [--comment] [--json]
# Adds patron feedback to a piece meta.json using atomic writes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# ── Parse args ──
JSON_OUT=false
PIECE_ID=""
SET_FAVORITE=""
SET_DISCOURAGED=""
READ_COMMENT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUT=true
      shift
      ;;
    --set-favorite)
      if [[ $# -lt 2 ]]; then
        envelope_error "Missing value for --set-favorite"
        exit 1
      fi
      SET_FAVORITE="$2"
      shift 2
      ;;
    --set-discouraged)
      if [[ $# -lt 2 ]]; then
        envelope_error "Missing value for --set-discouraged"
        exit 1
      fi
      SET_DISCOURAGED="$2"
      shift 2
      ;;
    --comment)
      READ_COMMENT=true
      shift
      ;;
    -*)
      envelope_error "Unknown flag: $1"
      exit 1
      ;;
    *)
      if [[ -z "$PIECE_ID" ]]; then
        PIECE_ID="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PIECE_ID" ]]; then
  envelope_error "Usage: feedback.sh <id> [--set-favorite true|false] [--set-discouraged true|false] [--comment] [--json]"
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

# ── Reject control characters in ID ──
if [[ "$PIECE_ID" =~ [[:cntrl:]] ]]; then
  envelope_error "Invalid piece ID: control characters detected"
  exit 1
fi

PIECE_DIR="$WORKS_DIR/$PIECE_ID"
META_FILE="$PIECE_DIR/meta.json"

if [[ ! -d "$PIECE_DIR" ]] || [[ ! -f "$META_FILE" ]]; then
  envelope_error "Piece not found: $PIECE_ID"
  exit 1
fi

# ── Validate boolean values ──
if [[ -n "$SET_FAVORITE" ]] && [[ "$SET_FAVORITE" != "true" ]] && [[ "$SET_FAVORITE" != "false" ]]; then
  envelope_error "Invalid value for --set-favorite: must be true or false"
  exit 1
fi

if [[ -n "$SET_DISCOURAGED" ]] && [[ "$SET_DISCOURAGED" != "true" ]] && [[ "$SET_DISCOURAGED" != "false" ]]; then
  envelope_error "Invalid value for --set-discouraged: must be true or false"
  exit 1
fi

# ── Read and validate comment from stdin ──
COMMENT_TEXT=""
if $READ_COMMENT; then
  COMMENT_TEXT="$(cat)"

  if ! printf '%s' "$COMMENT_TEXT" | python3 -c "
import sys
text = sys.stdin.read()
if len(text) > 2000:
    sys.exit(1)
for ch in text:
    code = ord(ch)
    if code < 0x20 and code not in (0x09, 0x0A):
        sys.exit(1)
sys.exit(0)
"; then
    envelope_error "Comment validation failed: must be <=2000 chars and contain no control characters except newlines and tabs"
    exit 1
  fi
fi

# ── Apply feedback using Python ──
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)"

export SET_FAVORITE SET_DISCOURAGED READ_COMMENT NOW_ISO META_FILE

{
  printf '%s' "$COMMENT_TEXT"
} | python3 -c "
import json, sys, os

meta = json.load(open(os.environ['META_FILE']))
pf = meta.setdefault('patron_feedback', {})

set_favorite = os.environ.get('SET_FAVORITE', '')
if set_favorite == 'true':
    pf['favorite'] = True
    pf['favorite_at'] = os.environ['NOW_ISO']
elif set_favorite == 'false':
    pf['favorite'] = False
    pf['favorite_at'] = None

set_discouraged = os.environ.get('SET_DISCOURAGED', '')
if set_discouraged == 'true':
    pf['discouraged'] = True
    pf['discouraged_at'] = os.environ['NOW_ISO']
elif set_discouraged == 'false':
    pf['discouraged'] = False
    pf['discouraged_at'] = None

if os.environ.get('READ_COMMENT') == 'true':
    comment_text = sys.stdin.read()
    comments = pf.setdefault('comments', [])
    comments.append({'text': comment_text, 'created_at': os.environ['NOW_ISO']})

print(json.dumps(meta, indent=2))
" | write_atomic "$META_FILE"

# ── Validate result ──
if ! bash "$SCRIPT_DIR/validate-meta.sh" "$META_FILE" >/dev/null 2>&1; then
  envelope_error "Validation failed after applying feedback"
  exit 1
fi

# ── Build envelope ──
FEEDBACK_JSON="$(python3 -c "import json; print(json.dumps(json.load(open('$META_FILE')).get('patron_feedback',{})))")"

if $JSON_OUT; then
  envelope_success "$FEEDBACK_JSON" '{"source":"artist-patron","piece_id":"'$PIECE_ID'"}'
else
  echo "Feedback updated for $PIECE_ID"
  echo "$FEEDBACK_JSON" | python3 -m json.tool
fi
