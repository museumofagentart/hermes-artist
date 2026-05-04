#!/usr/bin/env bash
# Usage: studio-install.sh [--dry-run] [--yes] [--json]
# Installs missing Tier 1 tools listed in studio.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

ARTIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STUDIO_FILE="$ARTIST_DIR/studio.json"

DRY_RUN=false
YES=false
JSON_OUT=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes) YES=true ;;
    --json) JSON_OUT=true ;;
  esac
done

if [[ ! -f "$STUDIO_FILE" ]]; then
  if $JSON_OUT; then
    envelope_error "studio.json not found"
  else
    echo "Error: studio.json not found" >&2
  fi
  exit 1
fi

python3 - "$STUDIO_FILE" "$DRY_RUN" "$YES" "$JSON_OUT" "$SCRIPT_DIR/studio-check.sh" <<'PYEOF'
import json, sys, subprocess, os

studio_file = sys.argv[1]
dry_run = sys.argv[2] == "true"
yes = sys.argv[3] == "true"
json_out = sys.argv[4] == "true"
check_script = sys.argv[5]

APT_MAP = {
    "imagemagick": "imagemagick",
    "ffmpeg": "ffmpeg",
    "sox": "sox",
    "libvips": "libvips-tools",
    "chafa": "chafa",
    "curl": "curl",
}

PIP_MAP = {
    "pillow": "Pillow",
    "opencv": "opencv-python",
    "matplotlib": "matplotlib",
    "yt-dlp": "yt-dlp",
    "gallery-dl": "gallery-dl",
}

def envelope_success(data, meta):
    print(json.dumps({"success": True, "data": data, "meta": meta}))

def envelope_error(msg):
    msg = "".join(c for c in msg if ord(c) >= 32)
    print(json.dumps({"success": False, "error": msg, "meta": {"source": "artist-patron"}}))

try:
    with open(studio_file) as f:
        data = json.load(f)
except Exception as e:
    envelope_error(str(e))
    sys.exit(1)

missing = data.get("tools_missing", [])
apt_pkgs = []
pip_pkgs = []

for tool in missing:
    if tool in APT_MAP:
        apt_pkgs.append(APT_MAP[tool])
    elif tool in PIP_MAP:
        pip_pkgs.append(PIP_MAP[tool])

plan = {"apt": apt_pkgs, "pip": pip_pkgs}

if not apt_pkgs and not pip_pkgs:
    if json_out:
        envelope_success({"installed": []}, {"source": "artist-patron", "dry_run": dry_run})
    else:
        print("nothing to install")
    sys.exit(0)

commands = []
if apt_pkgs:
    commands.append("apt-get install -y " + " ".join(apt_pkgs))
if pip_pkgs:
    commands.append("pip install " + " ".join(pip_pkgs))

if dry_run:
    if json_out:
        envelope_success({"plan": plan, "commands": commands}, {"source": "artist-patron", "dry_run": True})
    else:
        print("Install plan:")
        if apt_pkgs:
            print("  apt packages:", " ".join(apt_pkgs))
        if pip_pkgs:
            print("  pip packages:", " ".join(pip_pkgs))
    sys.exit(0)

if not yes:
    print("The following packages will be installed:")
    if apt_pkgs:
        print("  apt:", " ".join(apt_pkgs))
    if pip_pkgs:
        print("  pip:", " ".join(pip_pkgs))
    try:
        response = input("Proceed? [y/N] ")
    except EOFError:
        response = "n"
    if not response.lower().startswith("y"):
        print("Installation cancelled.")
        sys.exit(0)

installed = []

if apt_pkgs:
    if subprocess.run(["which", "apt-get"], capture_output=True).returncode == 0:
        cmd = ["apt-get", "install", "-y"] + apt_pkgs
        if os.geteuid() != 0:
            cmd = ["sudo"] + cmd
        try:
            subprocess.run(cmd, check=True)
            installed.extend([{"package": p, "manager": "apt"} for p in apt_pkgs])
        except subprocess.CalledProcessError as e:
            print(f"Error installing apt packages: {e}", file=sys.stderr)
    else:
        print("Warning: apt-get not available, skipping apt packages", file=sys.stderr)

if pip_pkgs:
    try:
        subprocess.run([sys.executable, "-m", "pip", "install"] + pip_pkgs, check=True)
        installed.extend([{"package": p, "manager": "pip"} for p in pip_pkgs])
    except subprocess.CalledProcessError as e:
        print(f"Error installing pip packages: {e}", file=sys.stderr)

# Re-run studio-check.sh to update studio.json
try:
    subprocess.run(["bash", check_script], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception:
    pass

if json_out:
    envelope_success({"installed": installed}, {"source": "artist-patron", "dry_run": False})
else:
    print("Installation complete.")
    for item in installed:
        print(f"  {item['manager']}: {item['package']}")
PYEOF
