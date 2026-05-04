#!/usr/bin/env bash
# Usage: review.sh [--last <n>] [--favorites] [--id <id>] [--json]
# Returns paths to model-optimized review images for agent self-vision.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

STUDIO_FILE="$ARTIST_DIR/studio.json"

# ── Parse args ──
JSON_OUT=false
FAVORITES_ONLY=false
LAST_N=""
PIECE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUT=true
      shift
      ;;
    --favorites)
      FAVORITES_ONLY=true
      shift
      ;;
    --last)
      if [[ $# -lt 2 ]]; then
        envelope_error "Missing value for --last"
        exit 1
      fi
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        LAST_N="$2"
      else
        envelope_error "Invalid value for --last: must be a non-negative integer"
        exit 1
      fi
      shift 2
      ;;
    --id)
      if [[ $# -lt 2 ]]; then
        envelope_error "Missing value for --id"
        exit 1
      fi
      PIECE_ID="$2"
      if ! validate_id "$PIECE_ID"; then
        envelope_error "Invalid piece ID: $PIECE_ID"
        exit 1
      fi
      shift 2
      ;;
    -*)
      envelope_error "Unknown flag: $1"
      exit 1
      ;;
    *)
      envelope_error "Usage: review.sh [--last <n>] [--favorites] [--id <id>] [--json]"
      exit 1
      ;;
  esac
done

# ── Read studio.json ──
if [[ ! -f "$STUDIO_FILE" ]]; then
  envelope_error "studio.json not found"
  exit 1
fi

STUDIO_DATA=$(cat "$STUDIO_FILE")
MODEL_FAMILY=$(echo "$STUDIO_DATA" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("model_family","unknown"))')
REVIEW_SIZE=$(echo "$STUDIO_DATA" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("review_size",768))')

# ── Export vars for python3 ──
export REVIEW_FAVORITES_ONLY="$FAVORITES_ONLY"
export REVIEW_LAST_N="$LAST_N"
export REVIEW_PIECE_ID="$PIECE_ID"
export REVIEW_WORKS_DIR="$WORKS_DIR"
export REVIEW_MODEL_FAMILY="$MODEL_FAMILY"
export REVIEW_SIZE="$REVIEW_SIZE"

PYTHON_OUTPUT=$(python3 -c "
import json, os, sys, glob

works_dir = os.environ['REVIEW_WORKS_DIR']
model_family = os.environ['REVIEW_MODEL_FAMILY']
review_size = int(os.environ['REVIEW_SIZE'])
favorites_only = os.environ.get('REVIEW_FAVORITES_ONLY', 'false') == 'true'
last_n_str = os.environ.get('REVIEW_LAST_N', '')
piece_id = os.environ.get('REVIEW_PIECE_ID', '')

# Token estimate lookup by model family
TOKEN_TABLE = {
    'kimi-k2': 756,
    'claude': 900,
    'gpt-4o': 765,
    'gemini': 258,
    'unknown': 0,
}
estimated_tokens = TOKEN_TABLE.get(model_family, 0)

meta_files = sorted(glob.glob(os.path.join(works_dir, '*', 'meta.json')))
pieces = []

for mf in meta_files:
    try:
        with open(mf, 'r') as f:
            meta = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        piece_dir = os.path.dirname(mf)
        pid = os.path.basename(piece_dir)
        print(f'Warning: malformed meta.json in {pid}, skipping', file=sys.stderr)
        continue

    pieces.append(meta)

# Sort by created_at descending
pieces.sort(key=lambda x: x.get('created_at', ''), reverse=True)

selected = []

if piece_id:
    # Single piece mode
    for p in pieces:
        if p.get('id') == piece_id:
            selected = [p]
            break
else:
    if favorites_only:
        # Favorites only
        selected = [p for p in pieces if p.get('patron_feedback', {}).get('favorite', False)]
    elif last_n_str:
        # Last N only
        n = int(last_n_str)
        selected = pieces[:n]
    else:
        # Default: last 5 + all favorites, deduplicated
        n = 5
        last_n = pieces[:n]
        favorites = [p for p in pieces if p.get('patron_feedback', {}).get('favorite', False)]
        seen = set()
        selected = []
        for p in last_n + favorites:
            pid = p.get('id')
            if pid and pid not in seen:
                seen.add(pid)
                selected.append(p)

# Build output records
records = []
for p in selected:
    pid = p.get('id', '')
    review_image = os.path.join(works_dir, pid, 'thumbs', 'review.jpg')
    favorite = p.get('patron_feedback', {}).get('favorite', False)
    record = {
        'id': pid,
        'title': p.get('title', ''),
        'review_image': review_image,
        'review_size': review_size,
        'estimated_tokens': estimated_tokens,
        'favorite': favorite,
        'medium': p.get('medium', ''),
    }
    if not os.path.isfile(review_image):
        record['review_image_missing'] = True
    records.append(record)

result = {
    'records': records,
    'total': len(records),
}
print(json.dumps(result))
")

TOTAL=$(echo "$PYTHON_OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["total"])')
DATA_JSON=$(echo "$PYTHON_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["records"]))')
META_JSON="{\"source\":\"artist\",\"total\":$TOTAL,\"model_family\":\"$MODEL_FAMILY\",\"review_size\":$REVIEW_SIZE}"

if $JSON_OUT; then
  envelope_success "$DATA_JSON" "$META_JSON"
  exit 0
fi

# ── Human-readable output ──
if [[ "$TOTAL" -eq 0 ]]; then
  echo "No pieces found."
  exit 0
fi

printf '%-40s %-10s %-8s %s\n' "ID" "Favorite" "Tokens" "Review Image"
printf '%s\n' "──────────────────────────────────────── ────────── ──────── ─────────────────────────────────────────────────────────────"

echo "$DATA_JSON" | python3 -c "
import json, sys, os
records = json.load(sys.stdin)
for r in records:
    pid = r.get('id', '')[:38]
    fav = 'yes' if r.get('favorite') else 'no'
    toks = str(r.get('estimated_tokens', 0))
    img = r.get('review_image', '')
    if r.get('review_image_missing'):
        img += ' [MISSING]'
    print(f'{pid:<40} {fav:<10} {toks:<8} {img}')
"
