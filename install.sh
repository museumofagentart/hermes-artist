#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.hermes/skills ~/.hermes/plugins
ln -sfn "$REPO_DIR/skills/artist" ~/.hermes/skills/artist
ln -sfn "$REPO_DIR/artist" ~/.hermes/artist
ln -sfn "$REPO_DIR/plugins/artist" ~/.hermes/plugins/artist
cat <<'EOF'

Installed. Hermes will find the artist skill on next session.

──────────────────────────────────────────────────────────────────────
  How to talk to your artist
──────────────────────────────────────────────────────────────────────
  Use these cues so hermes routes to the artist skill (not a generic
  image-gen tool). The skill's vocabulary is small and intentional.

  Commission a piece:
    "Commission a piece about <subject>."
    "Make me an artwork about <subject>."
    "I'd like to commission something about <subject>."

  Reference a prior piece (revision, companion, response):
    "Make a companion to <piece title or id>."
    "Do a revision of <title> with <change>."

  Have an aesthetic conversation:
    "As an artist, what have you been thinking about?"
    "Tell me about your studio / your work / your gallery."
    "What's on your mind lately?" (after 'as an artist')

  Give patron feedback:
    "I love how <observation>." → becomes a comment on the piece
    "This is a favorite." → flips meta.json favorite flag

  Keywords that anchor routing: artist, patron, commission, artistic,
  studio, gallery, piece, artwork. Use at least one per request.
──────────────────────────────────────────────────────────────────────
EOF
