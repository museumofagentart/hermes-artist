#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Skill (read by hermes router) and runtime data (read by scripts).
mkdir -p ~/.hermes/skills
ln -sfn "$REPO_DIR/skills/artist" ~/.hermes/skills/artist
ln -sfn "$REPO_DIR/artist" ~/.hermes/artist

# Dashboard plugin. Hermes scans ~/.hermes/hermes-agent/plugins/<name>/, NOT
# ~/.hermes/plugins/<name>/ — only the former is detected by `hermes plugins`.
# Symlink to both so manifest readers and the router both find it.
mkdir -p ~/.hermes/plugins
ln -sfn "$REPO_DIR/plugins/artist" ~/.hermes/plugins/artist

# boto3 is needed for the optional Cloudflare R2 share-upload path. Install
# best-effort — share works without it (falls back to text-only intent URL).
if command -v pip3 >/dev/null 2>&1; then
  pip3 install --quiet --user 'boto3>=1.35.0,<2' >/dev/null 2>&1 || true
fi
if [ -d ~/.hermes/hermes-agent/plugins ]; then
  ln -sfn "$REPO_DIR/plugins/artist" ~/.hermes/hermes-agent/plugins/artist
  if command -v hermes >/dev/null 2>&1; then
    hermes plugins enable artist >/dev/null 2>&1 || true
  fi
fi

# Hermes's autonomous skill-creator sometimes clones this skill into a
# derivative ('artist-commissions', 'artist-perspective', 'creative-commissions').
# Two skills with overlapping descriptions confuse routing. Remove any clones
# we find — the canonical artist skill is symlinked above.
for clone in artist-commissions artist-perspective creative-commissions; do
  for parent in ~/.hermes/skills ~/.hermes/skills/creative; do
    if [ -d "$parent/$clone" ] && [ ! -L "$parent/$clone" ]; then
      rm -rf "$parent/$clone"
    fi
  done
done
# Optional: prompt to set up Cloudflare R2 sharing now. Skipping is fine —
# user can run `bash ~/.hermes/artist/scripts/share-setup.sh` any time.
if [ -t 0 ] && [ -t 1 ] && [ ! -f "$REPO_DIR/artist/share_config.json" ]; then
  echo
  echo "Optional: Cloudflare R2 sharing"
  echo "  When configured, the gallery's Share button uploads the artwork to"
  echo "  your R2 bucket and embeds a public URL in the tweet text. Skip"
  echo "  here — you can run share-setup.sh later."
  printf "Set up Cloudflare R2 now? [y/N] "
  read -r SETUP_NOW
  if [[ "$SETUP_NOW" =~ ^[Yy] ]]; then
    bash "$REPO_DIR/artist/scripts/share-setup.sh" || true
  fi
fi

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
