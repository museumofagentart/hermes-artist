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

TITLE="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('title',''))")"
if [[ -f "$STATEMENT_FILE" ]]; then
  STATEMENT="$(cat "$STATEMENT_FILE")"
else
  STATEMENT=""
fi

# ── Get output file path ──
OUTPUT_FILE="$(python3 -c "import json; print(json.load(open('$META_FILE')).get('output_file',''))")"
OUTPUT_PATH="$PIECE_DIR/$OUTPUT_FILE"

# ── Try R2 upload (best-effort) ──
PUBLIC_URL="$(python3 - "$PIECE_DIR" "$OUTPUT_PATH" "$PIECE_ID" <<'PYEOF' 2>/dev/null || true
import json, sys, os
from pathlib import Path
piece_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])
piece_id = sys.argv[3]
meta_file = piece_dir / "meta.json"
try:
    meta = json.load(open(meta_file))
except Exception:
    sys.exit(0)
existing = meta.get("share") if isinstance(meta.get("share"), dict) else {}
cached = existing.get("r2_url") if existing else None
if cached:
    print(cached); sys.exit(0)
if not output_path.is_file():
    sys.exit(0)
# Locate r2_upload module installed alongside the dashboard plugin.
candidates = [
    Path.home() / ".hermes" / "plugins" / "artist" / "dashboard",
    Path(__file__).resolve().parents[2] / "plugins" / "artist" / "dashboard" if False else None,
]
# Try repo path relative to script dir as well.
script_dir = Path(os.environ.get("SCRIPT_DIR", "."))
repo_plugin = script_dir.parent.parent / "plugins" / "artist" / "dashboard"
candidates = [p for p in [Path.home() / ".hermes" / "plugins" / "artist" / "dashboard", repo_plugin] if p and p.is_dir()]
for c in candidates:
    sys.path.insert(0, str(c))
try:
    import r2_upload
except ImportError:
    sys.exit(0)
config = r2_upload.load_config()
if config is None:
    sys.exit(0)
object_key = f"{piece_id}/{output_path.name}"
try:
    url = r2_upload.upload_file(output_path, object_key, config)
except RuntimeError:
    sys.exit(0)
import datetime
meta["share"] = {
    "r2_url": url,
    "r2_object_key": object_key,
    "r2_bucket": config.bucket,
    "uploaded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
tmp = meta_file.with_suffix(".json.tmp")
tmp.write_text(json.dumps(meta, indent=2))
tmp.replace(meta_file)
print(url)
PYEOF
)"

# ── Build share text using shared excerpt logic from plugin_api ──
SHARE_TEXT="$(TITLE_ENV="$TITLE" PUBLIC_URL_ENV="$PUBLIC_URL" STATEMENT_ENV="$STATEMENT" python3 - <<'PYEOF'
import importlib.util, os
from pathlib import Path

title = os.environ.get("TITLE_ENV", "")
public_url = os.environ.get("PUBLIC_URL_ENV", "") or None
statement = os.environ.get("STATEMENT_ENV", "")

# Load plugin_api helpers from the dashboard plugin so CLI and dashboard share logic.
script_dir = Path(os.environ.get("SCRIPT_DIR", "."))
candidates = [
    Path.home() / ".hermes" / "plugins" / "artist" / "dashboard",
    script_dir.parent.parent / "plugins" / "artist" / "dashboard",
]
mod = None
for c in candidates:
    p = c / "plugin_api.py"
    if p.is_file():
        spec = importlib.util.spec_from_file_location("plugin_api", p)
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
            break
        except Exception:
            mod = None

if mod is None:
    # Minimal fallback if plugin not installed
    excerpt = " ".join(statement.split())[:180]
    parts = [p for p in [title, excerpt, public_url, "@agentartmuseum"] if p]
    print("\n\n".join(parts))
else:
    fixed = (len(title) + 2 if title else 0) + (25 if public_url else 0) + len("@agentartmuseum") + 2
    budget = max(80, 280 - fixed - 4)
    excerpt = mod._extract_statement_excerpt(statement, budget)
    print(mod._build_tweet_text(title, excerpt, public_url))
PYEOF
)"

ENCODED_TEXT="$(printf '%s' "$SHARE_TEXT" | python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()))')"
TWITTER_URL="https://twitter.com/intent/tweet?text=${ENCODED_TEXT}"

# ── Open browser if available ──
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$TWITTER_URL" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then
  open "$TWITTER_URL" >/dev/null 2>&1 || true
fi

# ── Output ──
if $JSON_OUT; then
  PUBLIC_URL_JSON="${PUBLIC_URL:-}"
  envelope_success "{\"url\":\"$TWITTER_URL\",\"output_path\":\"$OUTPUT_PATH\",\"public_url\":\"$PUBLIC_URL_JSON\"}" "{\"source\":\"artist\",\"piece_id\":\"$PIECE_ID\"}"
else
  if [[ -n "$PUBLIC_URL" ]]; then
    printf 'public: %s\n' "$PUBLIC_URL"
  elif [[ ! -f "$ARTIST_DIR/share_config.json" ]] && [[ -z "${CLOUDFLARE_R2_BUCKET:-}" ]]; then
    printf 'hint: bash ~/.hermes/artist/scripts/share-setup.sh to enable public-link sharing via Cloudflare R2\n' >&2
  fi
  printf '%s\n' "$TWITTER_URL"
fi
