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
  YOU are the sponsor / patron. The agent is the same hermes
  you already know, with a studio. You commission; they go to the
  studio and fulfill. (Sponsor = what you bear. Patron = the role.)

  Address the artist directly using the relationship's vocabulary —
  that's how hermes knows to load this skill instead of a generic
  image-gen tool.

  To COMMISSION (you, the patron):
    "Commission a piece about <subject>."
    "Make me an artwork about <subject>."
    "I'd like to commission something about <subject>."

  To reference a PRIOR PIECE (revision, companion, response):
    "Make a companion piece to <title or id>."
    "Commission a revision of <title> with <change>."

  To have an AESTHETIC CONVERSATION (perspective mode):
    "As an artist, what have you been thinking about?"
    "Tell me about your studio / your work / your gallery."

  To give PATRON FEEDBACK:
    "I love how <observation>." → becomes a comment on the piece
    "This is a favorite." → flips meta.json favorite flag

  Anchor vocabulary (use at least one): commission, artist, patron,
  studio, gallery, piece, artwork. Generic phrasing like "create an
  image" deliberately routes elsewhere.
──────────────────────────────────────────────────────────────────────
EOF
