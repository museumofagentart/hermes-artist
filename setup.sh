#!/usr/bin/env bash
# Setup for the artist-patron skill.
#
# What it does:
#   1. Registers this repo's skills/ dir in ~/.hermes/config.yaml
#   2. Symlinks the dashboard plugin into ~/.hermes/plugins/
#   3. Sets ARTIST_PATRON_HOME in ~/.hermes/.env so the studio resolves here
#   4. Installs boto3 (best-effort, for optional R2 share uploads)
#   5. Cleans up legacy symlinks from the old install.sh
#
# Idempotent — safe to re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$REPO_DIR/skills/artist-patron"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CONFIG_FILE="$HERMES_HOME/config.yaml"
ENV_FILE="$HERMES_HOME/.env"

echo "artist-patron setup"
echo "──────────────────────────────────────────────────────────────────────"
echo

# 1. Register skills dir in hermes config.yaml
if [ -f "$CONFIG_FILE" ]; then
  python3 - "$CONFIG_FILE" "$REPO_DIR/skills" <<'PY'
import sys, yaml, pathlib
config_path, skills_dir = pathlib.Path(sys.argv[1]), sys.argv[2]
cfg = yaml.safe_load(config_path.read_text()) or {}
skills = cfg.setdefault("skills", {})
dirs = skills.get("external_dirs") or []
if skills_dir not in dirs:
    dirs.append(skills_dir)
skills["external_dirs"] = dirs
config_path.write_text(yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False))
print(f"1. Registered {skills_dir} in {config_path} (skills.external_dirs)")
PY
else
  echo "1. SKIPPED: $CONFIG_FILE not found. Run hermes once to create it,"
  echo "   then re-run this script."
fi
echo

# 2. Plugin: symlink for dashboard
mkdir -p "$HERMES_HOME/plugins"
ln -sfn "$REPO_DIR/plugins/artist-patron" "$HERMES_HOME/plugins/artist-patron"
if command -v hermes >/dev/null 2>&1; then
  hermes plugins enable artist-patron >/dev/null 2>&1 || true
  echo "2. Dashboard plugin: linked and enabled."
else
  echo "2. Dashboard plugin: linked. Run 'hermes plugins enable artist-patron' once hermes is on PATH."
fi
echo

# 3. ARTIST_PATRON_HOME in hermes env
mkdir -p "$HERMES_HOME"
touch "$ENV_FILE"
if grep -q '^ARTIST_PATRON_HOME=' "$ENV_FILE" 2>/dev/null; then
  # Portable in-place edit (BSD + GNU sed)
  tmp="$(mktemp)"
  sed "s|^ARTIST_PATRON_HOME=.*|ARTIST_PATRON_HOME=$SKILL_DIR|" "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
else
  echo "ARTIST_PATRON_HOME=$SKILL_DIR" >> "$ENV_FILE"
fi
echo "3. Set ARTIST_PATRON_HOME=$SKILL_DIR in $ENV_FILE"
echo

# 4. boto3 for optional R2 sharing
if command -v pip3 >/dev/null 2>&1; then
  pip3 install --quiet --user 'boto3>=1.35.0,<2' >/dev/null 2>&1 || true
  echo "4. boto3 installed (for optional R2 share uploads)."
else
  echo "4. SKIPPED: pip3 not found. Install boto3 manually if you want R2 sharing."
fi
echo

# 5. Clean up legacy symlinks from old install.sh
removed=0
for legacy in "$HERMES_HOME/skills/artist" "$HERMES_HOME/artist" "$HERMES_HOME/plugins/artist"; do
  if [ -L "$legacy" ]; then
    rm -f "$legacy"
    removed=$((removed + 1))
  fi
done
if [ "$removed" -gt 0 ]; then
  echo "5. Removed $removed legacy artist symlink(s)."
fi

echo
echo "Done. Restart hermes (\`hermes gateway restart\`) to pick up the changes."
echo "──────────────────────────────────────────────────────────────────────"
