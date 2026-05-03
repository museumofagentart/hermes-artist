#!/usr/bin/env bash
# Usage: studio-check.sh [--json]
# Probes for each Tier 1 tool. Updates studio.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

ARTIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STUDIO_FILE="$ARTIST_DIR/studio.json"

JSON_OUT=false
if [[ "${1:-}" == "--json" ]]; then
  JSON_OUT=true
fi

python3 - "$STUDIO_FILE" << 'PYEOF'
import json, sys, subprocess, shutil, datetime

studio_file = sys.argv[1]

def run(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""

def py_version(mod):
    try:
        out = subprocess.run([sys.executable, "-c", f"import {mod}; print({mod}.__version__)"], capture_output=True, text=True, timeout=10).stdout.strip()
        return out if out else None
    except Exception:
        return None

def probe_cmd(cmd, version_cmd=None):
    path = shutil.which(cmd)
    if not path:
        return {"available": False, "version": None, "path": None}
    ver = None
    if version_cmd:
        out = run(version_cmd)
        if out:
            parts = out.split()
            if len(parts) >= 3:
                ver = parts[2]
            elif len(parts) >= 2:
                ver = parts[1]
    return {"available": True, "version": ver, "path": path}

tools = {}

# ImageMagick
tools["imagemagick"] = probe_cmd("magick", "magick --version")
if not tools["imagemagick"]["available"]:
    tools["imagemagick"] = probe_cmd("convert", "convert --version")

tools["ffmpeg"] = probe_cmd("ffmpeg", "ffmpeg -version")
tools["sox"] = probe_cmd("sox", "sox --version")
tools["libvips"] = probe_cmd("vips", "vips --version")
tools["chafa"] = probe_cmd("chafa", "chafa --version")

pil_ver = py_version("PIL")
tools["pillow"] = {"available": pil_ver is not None, "version": pil_ver, "path": None}

cv_ver = py_version("cv2")
tools["opencv"] = {"available": cv_ver is not None, "version": cv_ver, "path": None}

mpl_ver = py_version("matplotlib")
tools["matplotlib"] = {"available": mpl_ver is not None, "version": mpl_ver, "path": None}

tools["yt-dlp"] = probe_cmd("yt-dlp", "yt-dlp --version")
tools["curl"] = probe_cmd("curl", "curl --version")
tools["gallery-dl"] = probe_cmd("gallery-dl", "gallery-dl --version")

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

data = {
    "schema_version": "1",
    "setup_completed": True,
    "last_checked": now,
    "tools": tools,
    "review_size": 768,
    "model_family": "unknown",
}

with open(studio_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

if $JSON_OUT; then
  envelope_success "[]" '{"source":"artist","updated":true}'
else
  echo "Studio updated: $STUDIO_FILE"
fi
