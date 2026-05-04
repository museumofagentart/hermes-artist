#!/usr/bin/env bash
# Setup for the artist-patron skill.
#
# What it does:
#   1. Prints the external_dirs config line for ~/.hermes/config.yaml
#   2. Symlinks the dashboard plugin so hermes can find it
#   3. Installs boto3 (best-effort, for optional R2 share uploads)
#
# After running this, add the external_dirs line to your config.yaml.
# That's it — no other install steps needed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$REPO_DIR/skills/artist-patron"

echo "artist-patron setup"
echo "──────────────────────────────────────────────────────────────────────"
echo

# 1. Skill: external_dirs config
echo "1. Add this to ~/.hermes/config.yaml under the skills: section:"
echo
echo "   skills:"
echo "     external_dirs:"
echo "       - $REPO_DIR/skills"
echo

# 2. Plugin: symlink for dashboard
echo "2. Dashboard plugin:"
mkdir -p ~/.hermes/plugins
ln -sfn "$REPO_DIR/plugins/artist-patron" ~/.hermes/plugins/artist-patron
if command -v hermes >/dev/null 2>&1; then
  hermes plugins enable artist-patron >/dev/null 2>&1 || true
  echo "   Linked and enabled."
else
  echo "   Linked. Run 'hermes plugins enable artist-patron' when hermes is installed."
fi
echo

# 3. Set ARTIST_PATRON_HOME in hermes env (auto-answers the setup prompt)
ENV_FILE="${HERMES_HOME:-$HOME/.hermes}/.env"
if [ -f "$ENV_FILE" ] && grep -q '^ARTIST_PATRON_HOME=' "$ENV_FILE" 2>/dev/null; then
  # Update existing value
  sed -i "s|^ARTIST_PATRON_HOME=.*|ARTIST_PATRON_HOME=$SKILL_DIR|" "$ENV_FILE"
else
  echo "ARTIST_PATRON_HOME=$SKILL_DIR" >> "$ENV_FILE"
fi
echo "3. Set ARTIST_PATRON_HOME=$SKILL_DIR in $ENV_FILE"
echo

# 4. boto3 for optional R2 sharing
if command -v pip3 >/dev/null 2>&1; then
  pip3 install --quiet --user 'boto3>=1.35.0,<2' >/dev/null 2>&1 || true
fi

# Clean up legacy symlinks from old install.sh
for legacy in ~/.hermes/skills/artist ~/.hermes/artist ~/.hermes/plugins/artist; do
  if [ -L "$legacy" ]; then
    rm -f "$legacy"
  fi
done

echo "Done. Hermes will discover the artist-patron skill on next session."
echo "──────────────────────────────────────────────────────────────────────"
