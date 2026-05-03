# Tracer Bullet Report: hermes-da-kimi-c17

**Date:** 2026-05-03  
**Task:** Commission self-portrait, verify full loop (SKILL.md → agent creates → scripts read → feedback round-trips)  
**Model:** qwen3:8b via Ollama (local, 8B parameters)  
**Hermes:** v0.12.0  

---

## Summary

| Layer | Status | Notes |
|-------|--------|-------|
| Install / Symlinks | ✅ PASS | `install.sh` correctly linked `skills/artist`, `artist/`, and `plugins/artist` into `~/.hermes/`. |
| Hermes Config | ✅ PASS | Ollama provider configured; context-length and compression overrides applied to satisfy Hermes minimums. |
| Skill Loading | ✅ PASS | Skill appears in `Available Skills` list; SKILL.md injected into agent context. |
| Script Layer (manual) | ✅ PASS | `gallery.sh`, `show.sh`, `feedback.sh`, `validate-meta.sh` all behave correctly with a hand-crafted valid piece. |
| Agent Commission | ❌ FAIL | Agent could not complete the self-portrait commission. Stuck in tool-loop, invalid IDs, missing files. |
| Avatar / Thumbs | ⚠️ N/A | Validated manually; agent never produced them. |
| Closing Invitation | ❌ FAIL | Agent never reached the closing step. |

---

## Script-Layer Validation (Manual)

To prove the data layer works independently of the agent, a valid piece was created manually:

- **Piece ID:** `20260503-114412-1675-tracer-bullet`
- **Directory:** `~/.hermes/artist/works/20260503-114412-1675-tracer-bullet/`
- **Files:** `output.png`, `statement.md`, `process.md`, `meta.json`, `thumbs/thumb.jpg`, `thumbs/review.jpg`
- **Avatar:** `~/.hermes/artist/avatar.png` (512×512 PNG)

### Verification commands & results

```bash
# 1. meta.json passes schema validation
$ bash validate-meta.sh meta.json --json
{"success":true,"data":".../meta.json","meta":{"source":"artist","validated":true}}

# 2. gallery lists the piece
$ bash gallery.sh --json | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['meta']['total']>=1"
→ gallery OK: {'source': 'artist', 'total': 1, ...}

# 3. show returns full data
$ bash show.sh 20260503-114412-1675-tracer-bullet --json | python3 -c "... assert d['success']"
→ show OK: 20260503-114412-1675-tracer-bullet

# 4. Comment persists
$ echo "love it" | bash feedback.sh <id> --comment --json | python3 -c "... assert d['success']"
→ comment OK

# 5. Favorite persists
$ bash feedback.sh <id> --set-favorite true --json | python3 -c "... assert d['success']"
→ favorite OK

# 6. avatar.png is valid PNG >=256x256
$ python3 -c "from PIL import Image; img=Image.open('avatar.png'); assert img.format=='PNG' and img.width>=256"
→ avatar size: (512, 512)
```

**Conclusion:** The script envelope contract, atomic writes, input validation, and feedback round-trip are all solid.

---

## Agent-Layer Validation (Automated)

### Attempt 1 (ImageMagick missing, studio-check.sh stub)

- Agent tried `convert` → failed (ImageMagick not installed).
- Agent ran `studio-check.sh` (was a no-op stub) → reported zero tools.
- Agent ran `studio-install.sh` (was a no-op stub) → nothing installed.
- Agent attempted `brew install imagemagick@6` → timed out after 60 s.
- Session killed at 300 s.

**Fix applied during tracer:** Implemented `studio-check.sh` to detect real tools and report them in `studio.json`. Installed ImageMagick and chafa via Homebrew.

### Attempt 2 (Model stuck in ImageMagick label loop)

- Agent tried `magick -size 256x256 xc:gray ... label:"AI Artist"` → failed (font / syntax error).
- Agent iterated variations:
  - `-font Arial`
  - `-font DejaVu -pointsize 24`
- All variations failed with the same `[error]`.
- Agent never:
  - Created a piece directory with the correct ID format.
  - Wrote `meta.json`, `statement.md`, or `process.md`.
  - Generated thumbnails.
  - Copied output to `avatar.png`.
  - Closed with an invitation.

**Observed failure modes:**

1. **Invalid piece IDs** – The agent produced IDs like `20260503-014100-0001-selfportrait` (6-digit microseconds, missing hyphens in slug) and wrote directly to `works/` as a flat file rather than a directory.
2. **No tool fallback** – When ImageMagick `label:` failed, the agent did not switch to Pillow (which is available and reported in `studio.json`). It kept retrying the same failing approach.
3. **No stop-condition adherence** – The skill instructs: "Stop when you've made 3-5 substantive iterations... improvements are diminishing... you can articulate why the piece is done." The agent iterated the same failing command >5 times without progress.
4. **Insufficient model capability** – `qwen3:8b` is an 8B-parameter model. It cannot reliably follow the 10+ step creative workflow, file-layout requirements, and stop conditions described in SKILL.md.

---

## Root Cause Analysis

The **primary blocker** is model capability. The architecture (SKILL.md + scripts + filesystem layout) is correct, but the local 8B model cannot execute it.

Secondary issues that amplified the failure:

- **Missing `studio-check.sh` implementation** – Caused the agent to believe no tools were available on the first attempt. *(Fixed during tracer bullet.)*
- **Missing `review.sh`, `studio-install.sh`, `share.sh`** – Stubs are acceptable for a first pass, but `studio-install.sh` being a no-op meant the agent had to fall back to raw `brew install` calls.
- **No ID-generation helper** – The skill relies on the LLM to format a precise ID string. Weak models get this wrong consistently.

---

## Tickets Filed

| Ticket | Title | Rationale |
|--------|-------|-----------|
| [hermes-da-kimi-oyn](bd show hermes-da-kimi-oyn) | Add generate-piece-id helper script | Remove a failure mode for weak models by providing a script that emits a guaranteed-valid ID. |
| [hermes-da-kimi-ae0](bd show hermes-da-kimi-ae0) | Validate commission flow with a capable model | The tracer bullet must be rerun with a model that can reliably follow multi-step instructions (e.g., GPT-4o, Claude Sonnet, or 30B+ local). |
| [hermes-da-kimi-736](bd show hermes-da-kimi-736) | Implement review.sh with tests | Already existed; agent needs this for pre-commission portfolio review. |
| [hermes-da-kimi-vnh](bd show hermes-da-kimi-vnh) | Implement studio-install.sh with tests | Already existed; agent needs this for lazy tool installation. |

---

## Recommendations

1. **Merge the `studio-check.sh` implementation** included in this tracer-bullet branch. It accurately detects Tier 1 tools and updates `studio.json`.
2. **Add `generate-id.sh`** before the next tracer attempt so the agent does not need to synthesize IDs.
3. **Re-run the tracer bullet** with a commercial API or a 30B+ local model. The script layer is proven; we now need to prove the agent can drive it.
4. **Consider a fallback image-generation path in SKILL.md** – If ImageMagick is unavailable or fails, explicitly instruct the agent to use Pillow.

---

## Artifacts

- `artist/scripts/studio-check.sh` – implemented
- `artist/scripts/review.sh` – stub created
- `artist/scripts/studio-install.sh` – stub created
- `artist/scripts/share.sh` – stub created
- `tracer-report.md` – this document
