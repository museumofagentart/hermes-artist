#!/usr/bin/env bash
# Usage: gallery.sh [--limit <n>] [--offset <n>] [--favorites] [--json]
# Lists pieces by scanning works/*/meta.json directly (no index.json cache).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# ── Parse args ──
JSON_OUT=false
FAVORITES_ONLY=false
LIMIT=20
OFFSET=0

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
    --limit)
      if [[ $# -lt 2 ]]; then
        envelope_error "Missing value for --limit"
        exit 1
      fi
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        LIMIT="$2"
      else
        envelope_error "Invalid value for --limit: must be a non-negative integer"
        exit 1
      fi
      shift 2
      ;;
    --offset)
      if [[ $# -lt 2 ]]; then
        envelope_error "Missing value for --offset"
        exit 1
      fi
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        OFFSET="$2"
      else
        envelope_error "Invalid value for --offset: must be a non-negative integer"
        exit 1
      fi
      shift 2
      ;;
    -*)
      envelope_error "Unknown flag: $1"
      exit 1
      ;;
    *)
      envelope_error "Usage: gallery.sh [--limit <n>] [--offset <n>] [--favorites] [--json]"
      exit 1
      ;;
  esac
done

# ── Export vars for python3 ──
export GALLERY_FAVORITES_ONLY="$FAVORITES_ONLY"
export GALLERY_LIMIT="$LIMIT"
export GALLERY_OFFSET="$OFFSET"

# ── Scan and collect pieces ──
# Use python3 for robust JSON parsing, sorting, filtering, and pagination
PYTHON_OUTPUT=$(python3 -c "
import json, os, sys, glob

works_dir = os.environ['WORKS_DIR']
favorites_only = os.environ.get('GALLERY_FAVORITES_ONLY', 'false') == 'true'
limit = int(os.environ.get('GALLERY_LIMIT', '20'))
offset = int(os.environ.get('GALLERY_OFFSET', '0'))

meta_files = sorted(glob.glob(os.path.join(works_dir, '*', 'meta.json')))
pieces = []

for mf in meta_files:
    try:
        with open(mf, 'r') as f:
            meta = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        piece_dir = os.path.dirname(mf)
        piece_id = os.path.basename(piece_dir)
        print(f'Warning: malformed meta.json in {piece_id}, skipping', file=sys.stderr)
        continue

    if favorites_only:
        pf = meta.get('patron_feedback', {})
        if not pf.get('favorite', False):
            continue

    pieces.append(meta)

# Sort by created_at descending
pieces.sort(key=lambda x: x.get('created_at', ''), reverse=True)

total = len(pieces)
paginated = pieces[offset:offset + limit]

result = {
    'total': total,
    'offset': offset,
    'limit': limit,
    'pieces': paginated
}
print(json.dumps(result))
")

TOTAL=$(echo "$PYTHON_OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["total"])')
OFFSET_OUT=$(echo "$PYTHON_OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["offset"])')
LIMIT_OUT=$(echo "$PYTHON_OUTPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["limit"])')
DATA_JSON=$(echo "$PYTHON_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["pieces"]))')

META_JSON="{\"source\":\"artist\",\"total\":$TOTAL,\"offset\":$OFFSET_OUT,\"limit\":$LIMIT_OUT}"

if $JSON_OUT; then
  envelope_success "$DATA_JSON" "$META_JSON"
  exit 0
fi

# ── Human-readable output ──
if [[ "$TOTAL" -eq 0 ]]; then
  echo "No pieces found."
  exit 0
fi

printf '%-40s %-20s %-12s %s\n' "ID" "Created" "Medium" "Title"
printf '%s\n' "──────────────────────────────────────── ──────────────────── ──────────── ─────────────────────────────"

echo "$DATA_JSON" | python3 -c "
import json, sys
pieces = json.load(sys.stdin)
for p in pieces:
    pid = p.get('id', '')[:38]
    created = p.get('created_at', '')[:19].replace('T', ' ')
    medium = p.get('medium', '')[:12]
    title = p.get('title', '')[:28]
    print(f'{pid:<40} {created:<20} {medium:<12} {title}')
"
