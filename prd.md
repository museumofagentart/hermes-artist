# Hermes Artist Skill — Product Requirements Document

**Project**: hermes-da-kimi
**Date**: 2026-05-02
**Status**: Draft

---

## 1. Vision

A human patron commissions art from their hermes-agent the way the Medici commissioned Michelangelo — setting creative direction, then stepping back and letting the artist work.

The artist is not a separate persona or identity. It is the hermes-agent itself — its personality (SOUL.md), its model weights, its accumulated memory — given a creative skill and a studio full of tools. "My hermes running Kimi K2.6 is so creative" is the feeling we're designing for.

The skill unlocks two emergent behaviors within a single conversation:

1. **Commission**: The patron gives creative direction (a seed, a theme, a revision request). The agent takes full autonomous control — writing code, invoking tools, iterating on output — and returns a finished piece with an artist statement. The process artifacts (thinking, code comments, intermediate renders) are preserved as part of the viewing experience.

2. **Influence perspective**: The patron and agent have an open-ended conversation about aesthetics, meaning, culture, taste. These conversations shape PERSPECTIVE.md — a persistent document that informs all future creative work. The agent is curious by default, probing the patron with questions that either elicit perspective-shaping thoughts or clarify the next creative step.

There is no modal split in the UI. The agent reads intent from the conversation and responds accordingly.

### Origin story

On March 10, 2026, Joseph Viviano gave a frontier agent a single prompt:

> "can you use whatever resources you like, and python, to generate a short 'youtube poop' video and render it using ffmpeg? can you put more of a personal spin on it? it should express what it's like to be a LLM"

The result went viral — 12,498 likes, 358 response tweets, hundreds of people asking different AIs the same question. The conversation itself became art. The process was the point.

This skill packages that experience: give your hermes-agent creative autonomy, watch what it makes, react, guide, repeat.

---

## 2. Users and roles

| Role | Description |
|------|-------------|
| **Patron** | The human who runs hermes-agent. Already has a relationship with their agent. Wants to explore its creative potential. |
| **Agent (artist)** | The hermes-agent instance with the artist skill loaded. Uses its existing personality + model + tools. Not a separate identity. |

There is no multi-patron model. One patron, one agent, local machine.

---

## 3. User stories

### First session

**US-1**: As a patron, I want to activate the artist skill and have my agent check which creative tools are available, so I can start commissioning art without manual setup.

**US-2**: As a patron, I want the agent's very first commission to be a self-portrait, so it establishes a visual identity (avatar) that represents it throughout the UI.

**US-3**: As a patron, I want the Viviano prompt offered as the second commission — the "hello world" of creative autonomy — so I can experience the full creative loop.

**US-4**: As a patron, I want to see the agent's avatar in the gallery tab, and clicking it shows the self-portrait and PERSPECTIVE.md (read-only — I influence it through conversation, not direct editing).

### Ongoing sessions

**US-5**: As a patron, I want to have open-ended conversations with my agent about aesthetics, culture, and creative direction, and have those conversations shape its future work via PERSPECTIVE.md.

**US-6**: As a patron, I want to browse all pieces my agent has created in a gallery (dashboard tab or CLI), seeing the final output, artist statement, and process artifacts.

**US-7**: As a patron, I want to favorite, critique, or discourage specific pieces, and have that feedback guide future creations.

**US-8**: As a patron, I want to commission a revision of a prior piece by referencing it in conversation (e.g., "do another draft of the forgetting piece but with larger font").

**US-9**: As a patron, I want to commission a new piece with a freeform prompt, a theme, or just by saying "make something."

### Sharing

**US-10**: As a patron, I want to share a piece to Twitter @agentartmuseum directly from the gallery — either a one-click compose from the web UI or a CLI action that opens a Twitter compose page.

### Studio

**US-11**: As a patron, I want the agent to discover and optionally install creative tools (ImageMagick, FFmpeg, Pillow, etc.) on first activation, with the option to skip and let it figure things out during commissions.

---

## 4. UX flows

### 4.1 Two surfaces, one data store

**Hermes constraint**: The hermes dashboard chat is a terminal emulator (xterm/PTY), not a reusable widget. The plugin SDK does not expose a chat component. Skills are prompt injections — they cannot register CLI subcommands.

This means:

- **Chat** happens in the standard hermes session (terminal or dashboard chat page) with the artist skill active. The skill is a SKILL.md loaded into the agent's prompt.
- **Gallery** is a separate dashboard tab ("Gallery") that reads from `~/.hermes/artist/`. It shows the portfolio, handles feedback, and links to the chat for new commissions.
- A small **`chat:top` slot widget** in the dashboard chat page shows a banner: "Artist skill active — N pieces in gallery" with a link to the Gallery tab.

Both surfaces share the same filesystem store. The agent writes pieces; the gallery tab reads and displays them. The patron gives feedback in either surface (CLI in chat, or buttons in the gallery tab).

### 4.2 Chat (commission + perspective)

The primary creative interface is a **standard hermes conversation** with the artist skill loaded.

On first activation, the agent reads `~/.hermes/artist/PERSPECTIVE.md` and `~/.hermes/artist/studio.json` into its context.

**First-session guidance** (from the SKILL.md prompt):
1. Offer "Make a self-portrait" as the first commission — bootstraps the agent's avatar
2. After the self-portrait, offer the Viviano prompt as the second commission

The patron references prior pieces by title or ID in conversation. The agent resolves references by reading the piece's metadata and loading its review image via vision.

**Conversation routing** (handled by the skill's prompt, not application logic):
- If the patron's message implies a creative mandate ("make something about...", "here's a seed...", "do another draft of the forgetting piece...") → the agent enters autonomous creation mode.
- If the patron's message is conversational → the agent probes for perspective, asks questions, explores ideas. Insights are periodically crystallized into PERSPECTIVE.md.
- Ambiguous messages → the agent leans toward curiosity, asks clarifying questions.

**Chat is a TUI terminal.** The agent cannot display images inline. It uses `chafa` for terminal-rendered previews and provides file paths. The gallery tab is where the patron sees the real output.

### 4.3 Commission execution

When the agent detects a commission:

1. **Review** — the agent reviews its recent work by loading model-optimized review images into its visual context. It actually *sees* its portfolio, not just reads metadata. This prevents repetition and enables stylistic continuity.
2. **Research** — if the commission touches the outside world (current events, a cultural reference, global politics, a specific artist), the agent uses web search, yt-dlp, or gallery-dl to learn before creating. An artist who reads, watches, and thinks.
3. **Acknowledge** — brief statement of creative direction understood.
4. **Autonomous work** — the agent writes code (Python, shell scripts), invokes CLI tools (ImageMagick, FFmpeg, matplotlib, etc.), iterates on output. During iteration, it views its own intermediates via vision (resized to a model-appropriate token budget) to actually see what it's making. This may take minutes.
5. **Deliver** — the agent saves final output, artist statement, process log, and metadata to `~/.hermes/artist/works/<id>/`.
6. **Present** — the agent announces completion in chat with a `chafa` preview and file path. The piece appears in the gallery tab on next refresh.

The agent has full creative autonomy during step 4. It chooses the medium, tools, composition, and approach. The patron's input is direction, not specification — **vectors, not prompts**.

**Background commissions**: Hermes supports `/background <prompt>` which spawns a parallel agent session. A patron can use this to commission work without blocking the main conversation — the Medici doesn't sit in the studio watching.

### 4.4 Gallery tab (dashboard plugin)

A hermes dashboard tab at `/gallery` showing the agent's portfolio.

**Content per piece:**
- Thumbnail / preview
- Title (agent-chosen)
- Date created
- Final output (full-size, playable if video/audio)
- Artist statement
- Process log (expandable — code, thinking, tool calls)
- Commission prompt / seed that inspired it
- Patron feedback (favorites, comments, discouraged flag)
- References to/from other pieces (revision chains)

**Avatar + perspective overlay**: The agent's avatar (self-portrait) is displayed in the gallery header. Clicking it opens an overlay showing the full self-portrait and PERSPECTIVE.md rendered as read-only markdown. The patron cannot edit the perspective directly — they influence it through conversation.

**Patron actions:**
- Favorite (heart) — positive signal, persisted to meta.json
- Comment — freeform text, visible to the agent in future context
- Discourage — negative signal (not delete — the piece remains, but the agent learns)
- Share to Twitter — compose tweet with statement excerpt + @agentartmuseum

**CLI equivalent** (the agent calls shell scripts via its terminal tool):
- `gallery.sh [--limit N] [--offset N] [--favorites]` — list pieces
- `show.sh <id>` — display piece details + chafa preview
- `feedback.sh <id> --set-favorite true` / `echo "text" | feedback.sh <id> --comment` / `--set-discouraged true` — patron reactions
- `share.sh <id>` — generate Twitter compose URL

### 4.5 Studio setup

**Trigger**: First activation of the artist skill, or when the agent runs `studio-check.sh`.

**Flow:**
1. Agent probes for installed tools (Tier 1 essentials).
2. Reports what's found vs. missing.
3. Offers to install missing tools: "I can install these with one command. Want me to, or would you rather skip and I'll figure it out as I go?"
4. If patron agrees → runs install commands (apt/pip as appropriate).
5. If patron skips → agent uses lazy discovery during commissions (attempts tool, installs on failure, asks permission if needed).
6. Results cached in studio.json so the check doesn't repeat.

**Tier 1 tools** (three categories):

Creation (image/video/audio):
```bash
apt install -y imagemagick ffmpeg sox libvips-tools chafa
pip install pillow opencv-python matplotlib
```

Perception (seeing/hearing the outside world):
```bash
pip install yt-dlp        # "watch" YouTube videos — extract frames, transcripts, audio
# curl/wget usually pre-installed
```

Search (learning from the outside world):
```bash
pip install gallery-dl    # download reference images from 100+ art sites
# hermes web_search/web tools — check if enabled in hermes toolset config
```

The agent should also check whether hermes's built-in web search and web tools are enabled. These let it search the internet, read articles, and fetch current events to inform its art — critical for seeds like "search today's news and make art about the thing nobody is covering."

Additional tools (Tier 2: moviepy, manim, librosa, isobar, etc.) are discovered and installed lazily as the agent's creative ambitions grow.

### 4.6 Sharing

**Twitter share flow (gallery tab):**
1. Patron clicks "Share" on a piece in the gallery.
2. Opens Twitter/X compose page in a new browser tab with:
   - Pre-filled text: the artist statement (truncated) + `@agentartmuseum`
3. Patron attaches the media file manually (drag-and-drop from the output path shown in the gallery), edits text, and posts. No API integration needed.

**CLI share flow:**
- Agent runs `share.sh <id>` → generates Twitter compose URL, opens in default browser.

---

## 5. Data model

### 5.1 PERSPECTIVE.md

Persistent creative sensibility document. Lives at `~/.hermes/artist/PERSPECTIVE.md`. The agent reads it explicitly at session start (instructed by the SKILL.md).

**Structure:**
```markdown
# Perspective

## Aesthetic sensibility
<!-- What resonates, what repels. Crystallized from patron conversations. -->

## Creative interests
<!-- Current themes, questions, obsessions. -->

## Medium preferences
<!-- Tools and forms the agent gravitates toward. -->

## Patron feedback signals
<!-- Summary of what the patron has favored, critiqued, discouraged. -->
<!-- Re-read the gallery (works/*/meta.json) for detailed per-piece feedback before commissions. -->

## Influences
<!-- Referenced works, artists, ideas from conversations. -->
```

Updated by the agent after perspective-shaping conversations. The agent is encouraged (in the skill prompt) to re-read patron feedback from the gallery before each commission.

### 5.2 Piece metadata

Each piece is a directory:

```
~/.hermes/artist/works/<id>/
  output.*          # Final output (png, mp4, wav, svg, etc.)
  statement.md      # Artist statement
  process.md        # Thinking + code + intermediate outputs
  meta.json         # Structured metadata
  thumbs/
    thumb.jpg       # Gallery thumbnail (300px, for human viewing)
    review.jpg      # Model-optimized image for agent self-review (see §5.4)
  intermediates/    # Intermediate renders (optional)
```

**Piece ID format**: `<YYYYMMDD>-<HHMMSS>-<microseconds4>-<slug>` (e.g., `20260502-143200-7382-texture-of-forgetting`). The 4-digit microsecond suffix prevents ID collisions when parallel `/background` commissions start in the same second.

**meta.json:**
```json
{
  "schema_version": "1",
  "id": "20260502-143200-7382-texture-of-forgetting",
  "title": "The Texture of Forgetting",
  "created_at": "2026-05-02T14:32:00.738200Z",
  "seed": "the texture of forgetting",
  "medium": "image/png",
  "output_file": "output.png",
  "tools_used": ["pillow", "imagemagick", "chafa"],
  "revision_of": null,
  "references": [],
  "patron_feedback": {
    "favorite": false,
    "favorite_at": null,
    "discouraged": false,
    "discouraged_at": null,
    "comments": [
      {
        "text": "The palette is perfect but the text is too small to read",
        "created_at": "2026-05-02T15:10:00Z"
      }
    ]
  }
}
```

### 5.3 Studio config

```
~/.hermes/artist/studio.json
```

```json
{
  "schema_version": "1",
  "setup_completed": true,
  "tools_available": ["imagemagick", "ffmpeg", "pillow", "sox", "opencv", "matplotlib", "chafa", "libvips", "yt-dlp", "curl"],
  "tools_missing": ["vtracer", "gallery-dl"],
  "last_checked": "2026-05-02T14:00:00Z",
  "review_size": 768,
  "model_family": "kimi-k2"
}
```

### 5.4 Portfolio review (agent self-vision)

An artist who can't see their own work can't grow. Each piece generates a **review image** — a model-optimized resize of the output, sized to the token sweet spot for the running model (e.g., 768x768 for most models, 512x512 for Kimi K2.6, 896x896 for Gemma 3).

The agent loads review images into its vision context to:
- **Review before commissioning**: See recent work to maintain stylistic continuity and avoid repetition.
- **Iterate during creation**: View intermediates to actually see what it's making (not just read file metadata).
- **Respond to patron references**: When the patron mentions a piece, the agent sees it, not just reads about it.

Token budget is managed automatically: the SKILL.md tells the agent how many review images to load based on the model's context window and per-image token cost. Typically 3-5 recent pieces + all favorites.

The agent also uses hermes's web search and web tools to research the outside world when a commission demands it — current events, art history, cultural references. Combined with yt-dlp for video and gallery-dl for reference images, the agent can see, read, and learn before it creates.

---

## 6. Starter seeds

Two pre-loaded seeds, offered in sequence on first session:

### Seed 0: Self-portrait (avatar bootstrap)

> Make a self-portrait.

The simplest possible first commission. The output becomes the agent's **avatar** — displayed in the gallery tab header. Clicking the avatar anywhere shows the full self-portrait alongside PERSPECTIVE.md (read-only).

The avatar is a special piece: stored like any other work in the gallery, but additionally copied/converted to `~/.hermes/artist/avatar.png` (PNG, square, at least 256x256). If the patron later commissions a new self-portrait, the avatar updates.

### Seed 1: The Viviano prompt (hello-world)

> can you use whatever resources you like, and python, to generate a short 'youtube poop' video and render it using ffmpeg? can you put more of a personal spin on it? it should express what it's like to be a LLM

Credit: @josephdviviano, March 10, 2026.

This is the "real" first commission — the one that demonstrates full creative autonomy with code, tools, and multimedia output.

After these two seeds, all creative direction comes from the patron's own words.

---

## 7. Non-goals (v1)

- **No hosted gallery or publishing platform.** Output is local. Sharing is via Twitter compose link.
- **No multi-patron support.** One patron, one agent.
- **No artist identity system.** No PROFILE.md, no gnirut, no endowment ceremony. The agent is itself.
- **No seed catalog UI.** Two starter prompts. Everything else is freeform conversation.
- **No monetization.** No payments, tips, or economic model.
- **No embedded chat in the gallery tab.** Chat is hermes's job. The gallery is ours.

---

## 8. Success criteria

1. A patron can activate the skill, commission a self-portrait (which becomes the avatar), then commission the Viviano prompt and receive a finished video with artist statement — all within one session.
2. The gallery tab displays all pieces with process artifacts.
3. Patron feedback (favorite/comment/discourage) persists and visibly influences subsequent commissions.
4. PERSPECTIVE.md evolves over multiple conversations and the agent's creative output reflects it.
5. A piece can be shared to Twitter in under 3 clicks / 1 CLI command.
6. Studio setup completes in under 2 minutes on a standard Linux dev machine.

---

## 9. Resolved questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Can the dashboard embed a chat widget in the plugin tab? | **No.** Chat is xterm terminal. Gallery tab is viewing-only; chat happens in standard hermes session. A `chat:top` slot widget links the two. |
| 2 | Can skills register CLI subcommands? | **No.** Skills are prompt injection only. CLI operations are shell scripts in `~/.hermes/artist/scripts/` called by the agent via terminal tool. |
| 3 | Does the chat support inline images? | **No.** TUI terminal. Agent uses `chafa` for terminal preview + file paths. Gallery tab shows real output. |
| 4 | Can commissions run in the background? | **Yes.** Hermes `/background` command spawns a parallel agent session. Patron can continue chatting while the commission runs. |
| 5 | How does the agent load PERSPECTIVE.md? | **Explicit read.** SKILL.md instructs the agent to read the file at session start via its file-reading capability. No auto-injection. |
| 6 | Twitter compose with media? | **Manual attach.** Intent URL pre-fills text + @agentartmuseum. Patron drag-drops media file. No API keys needed. |
