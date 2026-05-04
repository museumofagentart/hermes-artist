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
import json, sys, subprocess, shutil, datetime, re, os

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

def extract_version(output, patterns):
    for pattern in patterns:
        m = re.search(pattern, output)
        if m:
            return m.group(1)
    return None

def probe_cmd(cmd, version_cmd=None, version_patterns=None):
    path = shutil.which(cmd)
    if not path:
        return {"available": False, "version": None, "path": None}
    ver = None
    if version_cmd:
        out = run(version_cmd)
        if out and version_patterns:
            ver = extract_version(out, version_patterns)
        if not ver and out:
            # fallback: first word that looks like a version
            for line in out.splitlines():
                for word in line.split():
                    if re.match(r'^\d+(\.\d+)+', word):
                        ver = word
                        break
                if ver:
                    break
    return {"available": True, "version": ver, "path": path}

tools = {}

# ImageMagick
tools["imagemagick"] = probe_cmd("magick", "magick --version", [r'ImageMagick\s+(\S+)'])
if not tools["imagemagick"]["available"]:
    tools["imagemagick"] = probe_cmd("convert", "convert --version", [r'ImageMagick\s+(\S+)'])

tools["ffmpeg"] = probe_cmd("ffmpeg", "ffmpeg -version", [r'version\s+(\S+)'])
tools["sox"] = probe_cmd("sox", "sox --version", [r'v?(\d+\.\d+\.\d+)', r'(\d+\.\d+\.\d+)'])
tools["libvips"] = probe_cmd("vips", "vips --version", [r'vips-?(\S+)'])
tools["chafa"] = probe_cmd("chafa", "chafa --version", [r'version\s+(\S+)'])

tools["python3"] = probe_cmd("python3", "python3 --version", [r'Python\s+(\S+)'])

pil_ver = py_version("PIL")
tools["pillow"] = {"available": pil_ver is not None, "version": pil_ver, "path": None}

cv_ver = py_version("cv2")
tools["opencv"] = {"available": cv_ver is not None, "version": cv_ver, "path": None}

mpl_ver = py_version("matplotlib")
tools["matplotlib"] = {"available": mpl_ver is not None, "version": mpl_ver, "path": None}

tools["yt-dlp"] = probe_cmd("yt-dlp", "yt-dlp --version", [r'(\S+)'])
tools["curl"] = probe_cmd("curl", "curl --version", [r'curl\s+(\S+)'])
tools["gallery-dl"] = probe_cmd("gallery-dl", "gallery-dl --version", [r'(\S+)'])

# Detect model family from hermes config
config_path = os.path.expanduser("~/.hermes/config.yaml")
model_family = "unknown"
review_size = 768

if os.path.exists(config_path):
    try:
        with open(config_path, "r") as f:
            config_text = f.read()
        # Simple YAML parsing: look for model.default and model.provider
        default_match = re.search(r'^model:\s*$', config_text, re.MULTILINE)
        model_section = ""
        if default_match:
            # Extract indented lines under model:
            lines = config_text[default_match.end():].splitlines()
            for line in lines:
                if line.startswith("  "):
                    model_section += line + "\n"
                elif line.strip() == "":
                    continue
                else:
                    break

        def_val = None
        prov_val = None
        for line in model_section.splitlines():
            m = re.match(r'^\s+default:\s*"?([^"\n]+)"?\s*$', line)
            if m:
                def_val = m.group(1).strip()
            m = re.match(r'^\s+provider:\s*"?([^"\n]+)"?\s*$', line)
            if m:
                prov_val = m.group(1).strip()

        combined = " ".join(filter(None, [def_val, prov_val])).lower()

        if "gemma" in combined:
            model_family = "gemma-3"
            review_size = 896
        elif "gemini" in combined:
            model_family = "gemini-2.5-pro"
            review_size = 768
        elif "glm" in combined:
            model_family = "glm-5v-turbo"
            review_size = 768
        elif "kimi" in combined:
            if "k2.6" in combined or (def_val and "kimi-k2.6" in def_val) or (prov_val and "kimi-k2.6" in prov_val):
                model_family = "kimi-k2.6"
                review_size = 512
            else:
                model_family = "kimi-k2"
                review_size = 768
        elif "claude" in combined or "anthropic" in combined:
            model_family = "claude"
            review_size = 768
        elif "gpt" in combined or "openai" in combined:
            model_family = "gpt"
            review_size = 768
        elif def_val or prov_val:
            model_family = "unknown"
            review_size = 768
    except Exception:
        model_family = "unknown"
        review_size = 768

tools_available = [name for name, info in tools.items() if info["available"]]
tools_missing = [name for name, info in tools.items() if not info["available"]]

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

data = {
    "schema_version": "1",
    "setup_completed": True,
    "last_checked": now,
    "tools": tools,
    "tools_available": tools_available,
    "tools_missing": tools_missing,
    "review_size": review_size,
    "model_family": model_family,
}

with open(studio_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

# Build envelope from the freshly-written studio.json
ENVELOPE_DATA=$(python3 -c "
import json
with open('$STUDIO_FILE') as f:
    d = json.load(f)
print(json.dumps({'available': d.get('tools_available', []), 'missing': d.get('tools_missing', [])}))
")

if $JSON_OUT; then
  envelope_success "$ENVELOPE_DATA" '{"source":"artist-patron","updated":true}'
else
  echo "Studio updated: $STUDIO_FILE"
fi
