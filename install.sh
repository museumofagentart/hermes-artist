#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.hermes/skills ~/.hermes/plugins
ln -sfn "$REPO_DIR/skills/artist" ~/.hermes/skills/artist
ln -sfn "$REPO_DIR/artist" ~/.hermes/artist
ln -sfn "$REPO_DIR/plugins/artist" ~/.hermes/plugins/artist
echo "Installed. Hermes will find the artist skill on next session."
