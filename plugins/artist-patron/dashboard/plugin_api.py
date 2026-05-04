"""Artist-patron dashboard plugin — backend API routes.

Mounted at /api/plugins/artist-patron/ by the dashboard plugin system.
Wraps filesystem reads in the standard envelope (EC§2).
"""

from __future__ import annotations

import json
import logging
import os
import re
import urllib.parse
from colorsys import rgb_to_hls, hls_to_rgb
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, field_validator

# r2_upload.py lives next to this file. Load it by absolute path so we work
# whether plugin_api is imported as a package member, a top-level module
# (tests inject sys.path), or by file-path loader (hermes web_server).
def _load_r2_upload():
    import importlib.util
    import sys as _sys
    from pathlib import Path
    mod_name = "artist_r2_upload"
    if mod_name in _sys.modules:
        return _sys.modules[mod_name]
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location(mod_name, here / "r2_upload.py")
    mod = importlib.util.module_from_spec(spec)
    # Register before exec so @dataclass can resolve cls.__module__ in sys.modules.
    _sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)
    return mod


r2_upload = _load_r2_upload()

log = logging.getLogger(__name__)

router = APIRouter()


def _resolve_artist_dir() -> Path:
    """Resolve the studio directory from ARTIST_PATRON_HOME env var.

    Falls back to ~/.hermes/artist for backward compatibility.
    """
    env = os.environ.get("ARTIST_PATRON_HOME")
    if env:
        return Path(env)
    return Path.home() / ".hermes" / "artist"


ARTIST_DIR: Path = _resolve_artist_dir()
WORKS_DIR: Path = ARTIST_DIR / "works"

PIECE_ID_RE = re.compile(r"^[0-9]{8}-[0-9]{6}-[0-9]{4}-[a-z0-9-]{1,40}$")
VALID_FEEDBACK_ACTIONS = {"favorite", "unfavorite", "discourage", "comment"}
MAX_COMMENT_LENGTH = 2000


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _envelope(success: bool, data: Any = None, meta: dict | None = None) -> dict:
    """Standard JSON envelope (EC§2)."""
    envelope = {
        "success": success,
        "data": data,
        "meta": {"source": "artist-patron"},
    }
    if meta:
        envelope["meta"].update(meta)
    return envelope


def _validate_piece_id(piece_id: str) -> Path:
    """Validate piece_id format and prevent path traversal (EC§7, EC§16)."""
    if not isinstance(piece_id, str) or not PIECE_ID_RE.match(piece_id):
        raise HTTPException(
            status_code=400,
            detail=_envelope(False, None, {"error": "invalid piece_id format"}),
        )
    # Explicit traversal guards (redundant with regex but defense in depth)
    if ".." in piece_id or "/" in piece_id or "%" in piece_id:
        raise HTTPException(
            status_code=400,
            detail=_envelope(False, None, {"error": "path traversal detected"}),
        )
    piece_dir = WORKS_DIR / piece_id
    # Resolve and verify containment within WORKS_DIR
    try:
        piece_dir.resolve().relative_to(WORKS_DIR.resolve())
    except (ValueError, RuntimeError):
        raise HTTPException(
            status_code=400,
            detail=_envelope(False, None, {"error": "path traversal detected"}),
        )
    return piece_dir


def _validate_comment(text: str | None) -> str | None:
    """Reject control characters except \\n and \\t; enforce max length (EC§16).

    Raises ValueError on validation failure so callers can format the envelope.
    """
    if text is None:
        return None
    if len(text) > MAX_COMMENT_LENGTH:
        raise ValueError(f"comment exceeds {MAX_COMMENT_LENGTH} characters")
    for ch in text:
        code = ord(ch)
        if code < 0x20 and ch not in "\n\t":
            raise ValueError("comment contains invalid control characters")
    return text


def _read_meta(piece_dir: Path) -> dict | None:
    """Read and parse meta.json; return None on malformed data."""
    meta_path = piece_dir / "meta.json"
    if not meta_path.is_file():
        return None
    try:
        with meta_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return None
        return data
    except (json.JSONDecodeError, OSError, UnicodeDecodeError) as exc:
        log.warning("Skipping malformed meta.json at %s: %s", meta_path, exc)
        return None


def _read_text(path: Path) -> str | None:
    """Read a text file; return None if missing or unreadable."""
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------------------
# Palette extraction
# ---------------------------------------------------------------------------

PALETTE_VERSION = 1


def _extract_palette(image_path: Path, num_colors: int = 5) -> list[dict] | None:
    """Quantize an image to *num_colors* dominant colours using Pillow MEDIANCUT.

    Returns a list of dicts sorted by pixel weight (most dominant first) or
    None when the image cannot be processed.
    """
    try:
        from PIL import Image
    except ImportError:
        log.debug("Pillow not available — palette extraction skipped")
        return None
    try:
        img = Image.open(image_path).convert("RGB")
        img.thumbnail((150, 150))
        quantized = img.quantize(colors=num_colors, method=Image.Quantize.MEDIANCUT)
        palette_data = quantized.getpalette()
        if palette_data is None:
            return None
        actual_colors = min(num_colors, len(palette_data) // 3)
        if actual_colors == 0:
            return None
        pixel_counts = quantized.histogram()[:actual_colors]
        total = sum(pixel_counts) or 1
        colors: list[dict] = []
        for i in range(actual_colors):
            r, g, b = palette_data[i * 3 : (i + 1) * 3]
            h, l, s = rgb_to_hls(r / 255, g / 255, b / 255)
            colors.append(
                {
                    "hex": f"#{r:02x}{g:02x}{b:02x}",
                    "rgb": [r, g, b],
                    "hls": [round(h, 3), round(l, 3), round(s, 3)],
                    "weight": round(pixel_counts[i] / total, 3),
                }
            )
        colors.sort(key=lambda c: c["weight"], reverse=True)
        return colors
    except Exception as exc:
        log.warning("Palette extraction failed for %s: %s", image_path, exc)
        return None


def _ensure_piece_palette(piece_dir: Path, meta: dict) -> list[dict] | None:
    """Return cached palette from meta or extract from thumbnail; persist on miss."""
    cached = meta.get("palette")
    if isinstance(cached, dict) and cached.get("version") == PALETTE_VERSION:
        return cached.get("colors")
    # Prefer thumbnail for speed; fall back to output file.
    thumb = piece_dir / "thumbs" / "thumb.jpg"
    if not thumb.is_file():
        output_file = meta.get("output_file")
        if output_file:
            thumb = piece_dir / output_file
    if not thumb.is_file():
        return None
    colors = _extract_palette(thumb)
    if colors is None:
        return None
    meta["palette"] = {"version": PALETTE_VERSION, "colors": colors}
    meta_path = piece_dir / "meta.json"
    try:
        with meta_path.open("w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
    except OSError as exc:
        log.warning("Could not persist palette to %s: %s", meta_path, exc)
    return colors


def _ensure_avatar_palette() -> list[dict] | None:
    """Return cached avatar palette or extract + cache to avatar_palette.json."""
    avatar_path = ARTIST_DIR / "avatar.png"
    if not avatar_path.is_file():
        return None
    cache_path = ARTIST_DIR / "avatar_palette.json"
    try:
        mtime = avatar_path.stat().st_mtime
    except OSError:
        return None
    if cache_path.is_file():
        try:
            with cache_path.open("r", encoding="utf-8") as f:
                cached = json.load(f)
            if (
                isinstance(cached, dict)
                and cached.get("version") == PALETTE_VERSION
                and cached.get("source_mtime") == mtime
            ):
                return cached.get("colors")
        except (json.JSONDecodeError, OSError):
            pass
    colors = _extract_palette(avatar_path)
    if colors is None:
        return None
    try:
        with cache_path.open("w", encoding="utf-8") as f:
            json.dump(
                {"version": PALETTE_VERSION, "colors": colors, "source_mtime": mtime},
                f,
                indent=2,
            )
    except OSError as exc:
        log.warning("Could not cache avatar palette: %s", exc)
    return colors


def _relative_luminance(r: float, g: float, b: float) -> float:
    """WCAG relative luminance from linear-sRGB 0-1 values."""

    def _lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def _contrast_ratio(lum1: float, lum2: float) -> float:
    lighter = max(lum1, lum2)
    darker = min(lum1, lum2)
    return (lighter + 0.05) / (darker + 0.05)


def _pick_candidate(colors: list[dict], kind: str) -> list[int] | None:
    """Pick the heaviest colour matching *kind* ('dark' or 'light')."""
    for c in colors:  # already sorted by weight desc
        lightness = c["hls"][1]
        if kind == "dark" and lightness < 0.35:
            return c["rgb"]
        if kind == "light" and lightness > 0.55:
            return c["rgb"]
    return None


def _pick_accent(colors: list[dict]) -> list[int] | None:
    """Pick the most saturated warm-hue colour for --color-warning / accent.

    Prefers hues in the warm range (red-orange-yellow, H 0.0-0.18 or 0.85-1.0)
    with saturation > 0.3. Falls back to the most saturated colour overall.
    """
    best_warm: dict | None = None
    best_any: dict | None = None
    for c in colors:
        h, _l, s = c["hls"]
        if s < 0.2:
            continue
        if best_any is None or s > best_any["hls"][2]:
            best_any = c
        if (h <= 0.18 or h >= 0.85) and s > 0.3:
            if best_warm is None or s > best_warm["hls"][2]:
                best_warm = c
    chosen = best_warm or best_any
    return chosen["rgb"] if chosen else None


def _weighted_avg(candidates: list[tuple[list[int], float]]) -> list[int]:
    """Weighted average of RGB triplets."""
    total_w = sum(w for _, w in candidates)
    if total_w == 0:
        return [0, 0, 0]
    r = sum(c[0] * w for c, w in candidates) / total_w
    g = sum(c[1] * w for c, w in candidates) / total_w
    b = sum(c[2] * w for c, w in candidates) / total_w
    return [int(round(r)), int(round(g)), int(round(b))]


def _rgb_to_hex(rgb: list[int]) -> str:
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"


def _ensure_contrast(bg_rgb: list[int], mg_rgb: list[int]) -> tuple[list[int], list[int]]:
    """Adjust midground lightness up until WCAG 4.5:1 contrast is met."""
    bg_lum = _relative_luminance(bg_rgb[0] / 255, bg_rgb[1] / 255, bg_rgb[2] / 255)
    mg_lum = _relative_luminance(mg_rgb[0] / 255, mg_rgb[1] / 255, mg_rgb[2] / 255)
    if _contrast_ratio(bg_lum, mg_lum) >= 4.5:
        return bg_rgb, mg_rgb
    # Bump midground lightness
    h, l, s = rgb_to_hls(mg_rgb[0] / 255, mg_rgb[1] / 255, mg_rgb[2] / 255)
    for _ in range(50):
        l = min(1.0, l + 0.03)
        r2, g2, b2 = hls_to_rgb(h, l, s)
        new_lum = _relative_luminance(r2, g2, b2)
        if _contrast_ratio(bg_lum, new_lum) >= 4.5:
            return bg_rgb, [int(round(r2 * 255)), int(round(g2 * 255)), int(round(b2 * 255))]
    # Last resort: use adjusted value anyway
    r2, g2, b2 = hls_to_rgb(h, l, s)
    return bg_rgb, [int(round(r2 * 255)), int(round(g2 * 255)), int(round(b2 * 255))]


def _compose_gallery_palette(
    avatar_colors: list[dict] | None,
    piece_palettes: list[list[dict]],
) -> dict | None:
    """Compose a gallery-wide palette from avatar + up to 3 recent pieces.

    Returns dict with background, midground, warmGlow, accent keys or None.
    """
    bg_candidates: list[tuple[list[int], float]] = []
    mg_candidates: list[tuple[list[int], float]] = []
    accent_candidates: list[list[dict]] = []

    if avatar_colors:
        bg = _pick_candidate(avatar_colors, "dark")
        mg = _pick_candidate(avatar_colors, "light")
        if bg:
            bg_candidates.append((bg, 0.55))
        if mg:
            mg_candidates.append((mg, 0.55))
        accent_candidates.append(avatar_colors)

    piece_weight = 0.15
    for pc in piece_palettes[:3]:
        bg = _pick_candidate(pc, "dark")
        mg = _pick_candidate(pc, "light")
        if bg:
            bg_candidates.append((bg, piece_weight))
        if mg:
            mg_candidates.append((mg, piece_weight))
        accent_candidates.append(pc)

    if not bg_candidates or not mg_candidates:
        return None

    final_bg = _weighted_avg(bg_candidates)
    final_mg = _weighted_avg(mg_candidates)
    final_bg, final_mg = _ensure_contrast(final_bg, final_mg)

    # Accent: pick from all source palettes combined
    all_colors = [c for pal in accent_candidates for c in pal]
    accent_rgb = _pick_accent(all_colors)
    accent_hex = _rgb_to_hex(accent_rgb) if accent_rgb else None

    warm_glow = f"rgba({final_mg[0]}, {final_mg[1]}, {final_mg[2]}, 0.30)"

    return {
        "background": _rgb_to_hex(final_bg),
        "midground": _rgb_to_hex(final_mg),
        "warmGlow": warm_glow,
        "accent": accent_hex,
    }


# ---------------------------------------------------------------------------
# Sensors
# ---------------------------------------------------------------------------


@router.get("/avatar")
async def get_avatar():
    """Serve avatar.png. 404 if no self-portrait yet."""
    avatar_path = ARTIST_DIR / "avatar.png"
    if avatar_path.is_file():
        return FileResponse(str(avatar_path), media_type="image/png")
    return Response(
        content=json.dumps(_envelope(False, None, {"error": "avatar not found"})),
        status_code=404,
        media_type="application/json",
    )


@router.get("/identity")
async def get_identity():
    """Avatar path + PERSPECTIVE.md content (read-only). For the avatar overlay."""
    avatar_path = ARTIST_DIR / "avatar.png"
    perspective = _read_text(ARTIST_DIR / "PERSPECTIVE.md")
    return _envelope(
        True,
        {
            "avatar_exists": avatar_path.is_file(),
            "avatar_path": str(avatar_path) if avatar_path.is_file() else None,
            "perspective": perspective or "",
        },
    )


@router.get("/gallery")
async def gallery(limit: int = 20, offset: int = 0, favorites: bool = False):
    """Paginated piece listing. EC§5.

    Scans works/*/meta.json on every call (no index.json). Supports
    pagination and optional favorites-only filter.
    """
    pieces: list[dict] = []
    if WORKS_DIR.is_dir():
        for piece_dir in sorted(WORKS_DIR.iterdir()):
            if not piece_dir.is_dir():
                continue
            meta = _read_meta(piece_dir)
            if meta is None:
                continue
            # Validate id matches directory name (defensive)
            if meta.get("id") != piece_dir.name:
                log.warning(
                    "meta.json id mismatch: dir=%s meta.id=%s",
                    piece_dir.name,
                    meta.get("id"),
                )
                continue
            feedback = meta.get("patron_feedback", {})
            if favorites and not feedback.get("favorite", False):
                continue
            pieces.append(meta)

    # Sort by created_at descending (newest first)
    pieces.sort(key=lambda p: p.get("created_at", ""), reverse=True)

    total = len(pieces)
    paginated = pieces[offset : offset + limit] if limit > 0 else pieces[offset:]

    return _envelope(
        True,
        paginated,
        {"total": total, "offset": offset, "limit": limit, "favorites_filter": favorites},
    )


@router.get("/pieces/{piece_id}")
async def get_piece(piece_id: str):
    """Full piece detail: meta + statement + process log."""
    piece_dir = _validate_piece_id(piece_id)
    meta = _read_meta(piece_dir)
    if meta is None:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "piece not found"})),
            status_code=404,
            media_type="application/json",
        )
    statement = _read_text(piece_dir / "statement.md")
    process = _read_text(piece_dir / "process.md")
    return _envelope(
        True,
        {
            "meta": meta,
            "statement": statement,
            "process": process,
        },
    )


@router.get("/pieces/{piece_id}/output")
async def get_output(piece_id: str):
    """Serve the output file (image/video/audio)."""
    piece_dir = _validate_piece_id(piece_id)
    meta = _read_meta(piece_dir)
    if meta is None:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "piece not found"})),
            status_code=404,
            media_type="application/json",
        )
    output_file = meta.get("output_file")
    if not output_file:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "output_file not defined in meta"})),
            status_code=404,
            media_type="application/json",
        )
    output_path = piece_dir / output_file
    if not output_path.is_file():
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "output file not found"})),
            status_code=404,
            media_type="application/json",
        )
    # Derive media type from meta if available
    media_type = meta.get("medium", "application/octet-stream")
    return FileResponse(str(output_path), media_type=media_type)


@router.get("/pieces/{piece_id}/thumb")
async def get_thumb(piece_id: str):
    """Serve thumbnail for gallery grid."""
    piece_dir = _validate_piece_id(piece_id)
    thumb_path = piece_dir / "thumbs" / "thumb.jpg"
    if thumb_path.is_file():
        return FileResponse(str(thumb_path), media_type="image/jpeg")
    return Response(
        content=json.dumps(_envelope(False, None, {"error": "thumbnail not found"})),
        status_code=404,
        media_type="application/json",
    )


@router.get("/review")
async def review(last: int = 5, favorites: bool = True, piece_id: str | None = None):
    """Return review image paths for agent self-vision."""
    if piece_id is not None:
        piece_dir = _validate_piece_id(piece_id)
        meta = _read_meta(piece_dir)
        if meta is None:
            return Response(
                content=json.dumps(_envelope(False, None, {"error": "piece not found"})),
                status_code=404,
                media_type="application/json",
            )
        review_path = piece_dir / "thumbs" / "review.jpg"
        return _envelope(
            True,
            [
                {
                    "id": meta.get("id"),
                    "title": meta.get("title"),
                    "review_image": str(review_path) if review_path.is_file() else None,
                    "favorite": meta.get("patron_feedback", {}).get("favorite", False),
                    "medium": meta.get("medium"),
                }
            ],
            {"total": 1},
        )

    # Collect pieces
    all_pieces: list[dict] = []
    if WORKS_DIR.is_dir():
        for piece_dir in sorted(WORKS_DIR.iterdir()):
            if not piece_dir.is_dir():
                continue
            meta = _read_meta(piece_dir)
            if meta is None:
                continue
            all_pieces.append(meta)

    # Sort by created_at descending
    all_pieces.sort(key=lambda p: p.get("created_at", ""), reverse=True)

    selected: list[dict] = []
    seen_ids: set[str] = set()

    # Last N pieces
    for meta in all_pieces[:last]:
        selected.append(meta)
        seen_ids.add(meta.get("id"))

    # Favorites (if enabled)
    if favorites:
        for meta in all_pieces:
            if meta.get("id") in seen_ids:
                continue
            if meta.get("patron_feedback", {}).get("favorite", False):
                selected.append(meta)
                seen_ids.add(meta.get("id"))

    results = []
    for meta in selected:
        piece_dir = WORKS_DIR / meta.get("id", "")
        review_path = piece_dir / "thumbs" / "review.jpg"
        results.append(
            {
                "id": meta.get("id"),
                "title": meta.get("title"),
                "review_image": str(review_path) if review_path.is_file() else None,
                "favorite": meta.get("patron_feedback", {}).get("favorite", False),
                "medium": meta.get("medium"),
            }
        )

    return _envelope(True, results, {"total": len(results), "last": last, "favorites": favorites})


@router.get("/studio")
async def studio_status():
    """Current tool availability from studio.json."""
    studio_path = ARTIST_DIR / "studio.json"
    if studio_path.is_file():
        try:
            with studio_path.open("r", encoding="utf-8") as f:
                data = json.load(f)
            return _envelope(True, data)
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("Malformed studio.json: %s", exc)
            return Response(
                content=json.dumps(_envelope(False, None, {"error": "malformed studio.json"})),
                status_code=500,
                media_type="application/json",
            )
    return Response(
        content=json.dumps(_envelope(False, None, {"error": "studio.json not found"})),
        status_code=404,
        media_type="application/json",
    )


@router.get("/perspective")
async def get_perspective():
    """PERSPECTIVE.md contents (read-only)."""
    perspective = _read_text(ARTIST_DIR / "PERSPECTIVE.md")
    if perspective is None:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "PERSPECTIVE.md not found"})),
            status_code=404,
            media_type="application/json",
        )
    return _envelope(True, {"content": perspective})


@router.get("/palette")
async def get_palette():
    """Gallery colour palette derived from avatar + 3 most recent still images.

    Extracts dominant colours, composes them into a background/midground pair,
    and returns hex values the frontend applies as CSS custom property overrides.
    """
    avatar_colors = _ensure_avatar_palette()

    # Collect recent still-image pieces
    piece_palettes: list[list[dict]] = []
    source_piece_ids: list[str] = []
    if WORKS_DIR.is_dir():
        pieces: list[tuple[str, dict]] = []
        for piece_dir in WORKS_DIR.iterdir():
            if not piece_dir.is_dir():
                continue
            meta = _read_meta(piece_dir)
            if meta is None:
                continue
            medium = meta.get("medium", "")
            if not isinstance(medium, str) or not medium.startswith("image/"):
                continue
            pieces.append((meta.get("created_at", ""), meta, piece_dir))
        pieces.sort(key=lambda t: t[0], reverse=True)
        for _, meta, piece_dir in pieces[:3]:
            colors = _ensure_piece_palette(piece_dir, meta)
            if colors:
                piece_palettes.append(colors)
                source_piece_ids.append(meta.get("id", piece_dir.name))

    composed = _compose_gallery_palette(avatar_colors, piece_palettes)
    if composed is None:
        return _envelope(True, None, {
            "debug": {
                "avatar_colors_count": len(avatar_colors) if avatar_colors else 0,
                "piece_palettes_count": len(piece_palettes),
                "source_piece_ids": source_piece_ids,
            }
        })

    composed["sources"] = {
        "avatar": avatar_colors is not None,
        "pieces": source_piece_ids,
    }
    return _envelope(True, composed)


# ---------------------------------------------------------------------------
# Actuators
# ---------------------------------------------------------------------------


class FeedbackBody(BaseModel):
    action: str
    comment: Optional[str] = None

    @field_validator("action")
    @classmethod
    def _validate_action(cls, v: str) -> str:
        if v not in VALID_FEEDBACK_ACTIONS:
            raise ValueError(f"invalid action: {v!r}")
        return v


@router.post("/pieces/{piece_id}/feedback")
async def add_feedback(piece_id: str, body: FeedbackBody):
    """Add patron feedback.

    action: favorite|unfavorite|discourage|comment.
    EC§7: validate action enum at boundary.
    EC§9: append-only comments; idempotent flags.
    EC§16: reject control chars, path traversal.
    """
    piece_dir = _validate_piece_id(piece_id)
    meta = _read_meta(piece_dir)
    if meta is None:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "piece not found"})),
            status_code=404,
            media_type="application/json",
        )

    # Validate comment text if present
    try:
        comment_text = _validate_comment(body.comment)
    except ValueError as exc:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": str(exc)})),
            status_code=400,
            media_type="application/json",
        )

    feedback = meta.setdefault("patron_feedback", {})
    now = datetime.now(timezone.utc).isoformat()

    if body.action == "favorite":
        feedback["favorite"] = True
        feedback["favorite_at"] = now
    elif body.action == "unfavorite":
        feedback["favorite"] = False
        feedback["favorite_at"] = None
    elif body.action == "discourage":
        feedback["discouraged"] = True
        feedback["discouraged_at"] = now
    elif body.action == "comment":
        if not comment_text:
            return Response(
                content=json.dumps(_envelope(False, None, {"error": "comment text is required for action=comment"})),
                status_code=400,
                media_type="application/json",
            )
        comments = feedback.setdefault("comments", [])
        comments.append({"text": comment_text, "created_at": now})

    # Persist updated meta.json
    meta_path = piece_dir / "meta.json"
    try:
        with meta_path.open("w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
    except OSError as exc:
        log.error("Failed to write meta.json: %s", exc)
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "failed to persist feedback"})),
            status_code=500,
            media_type="application/json",
        )

    return _envelope(True, feedback)


def _persist_share_state(piece_dir: Path, meta: dict, share_state: dict) -> None:
    """Update meta.json with the share block. Best-effort; logs on failure."""
    meta["share"] = share_state
    meta_path = piece_dir / "meta.json"
    try:
        with meta_path.open("w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
    except OSError as exc:
        log.warning("Could not persist share state to %s: %s", meta_path, exc)


_MD_BOLD_RE = re.compile(r"\*\*([^*]+)\*\*")
_MD_ITALIC_RE = re.compile(r"(?<!\*)\*([^*]+)\*(?!\*)")
_MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]+\)")
_MD_INLINE_CODE_RE = re.compile(r"`([^`]+)`")
_WS_RUN_RE = re.compile(r"\s+")


def _strip_markdown(text: str) -> str:
    """Strip basic markdown syntax for clean tweet text."""
    text = _MD_LINK_RE.sub(r"\1", text)
    text = _MD_BOLD_RE.sub(r"\1", text)
    text = _MD_ITALIC_RE.sub(r"\1", text)
    text = _MD_INLINE_CODE_RE.sub(r"\1", text)
    return text


def _extract_statement_excerpt(statement_md: str, max_chars: int) -> str:
    """Pull a clean prose excerpt from a piece's statement.md.

    Skips the title heading and any metadata block (lines like **Medium:** …,
    **Tools:** …, **Created:** …). Prefers the body under '## Statement' if
    present, else the first prose paragraph. Strips markdown and collapses
    whitespace. Truncates at sentence/word boundary with an ellipsis.
    """
    if not statement_md:
        return ""

    # Prefer text under a "## Statement" section, else everything.
    body = statement_md
    parts = re.split(r"(?im)^##\s*statement\s*$", statement_md, maxsplit=1)
    if len(parts) == 2:
        body = parts[1]

    # Take the first non-metadata paragraph.
    paragraphs = re.split(r"\n\s*\n", body.strip())
    excerpt = ""
    for p in paragraphs:
        # Skip headings, lists, and metadata-style **Key:** value lines
        stripped = p.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            continue
        # If every non-empty line is a **Key:** … bold-prefixed metadata row, skip.
        lines = [ln.strip() for ln in stripped.splitlines() if ln.strip()]
        if lines and all(re.match(r"^\*\*[^*]+:\*\*", ln) for ln in lines):
            continue
        excerpt = stripped
        break

    excerpt = _strip_markdown(excerpt)
    excerpt = _WS_RUN_RE.sub(" ", excerpt).strip()

    if len(excerpt) <= max_chars:
        return excerpt

    # Truncate at last sentence boundary within budget, else at word boundary.
    truncated = excerpt[: max_chars - 1]
    for end in (". ", "? ", "! "):
        idx = truncated.rfind(end)
        if idx >= max_chars * 0.5:
            return truncated[: idx + 1].rstrip()
    word_idx = truncated.rfind(" ")
    if word_idx >= max_chars * 0.5:
        truncated = truncated[:word_idx]
    return truncated.rstrip(" ,;:") + "…"


def _build_tweet_text(title: str, excerpt: str, public_url: str | None) -> str:
    """Compose the tweet: title, excerpt, URL, then handle on its own line.

    Twitter wraps any URL into a 23-char t.co link automatically when posted.
    """
    parts: list[str] = []
    if title:
        parts.append(title.strip())
    if excerpt:
        parts.append(excerpt)
    if public_url:
        parts.append(public_url)
    parts.append("@agentartmuseum")
    return "\n\n".join(parts)


@router.post("/pieces/{piece_id}/share")
async def share_piece(piece_id: str):
    """Generate a Twitter compose URL.

    If Cloudflare R2 is configured, upload the artwork first and embed
    the public URL in the share text. The uploaded URL is cached in
    meta.json under `share.r2_url` so re-clicks don't re-upload.
    Falls back to a text-only intent URL when R2 isn't configured or
    the upload fails.
    """
    piece_dir = _validate_piece_id(piece_id)
    meta = _read_meta(piece_dir)
    if meta is None:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "piece not found"})),
            status_code=404,
            media_type="application/json",
        )

    statement = _read_text(piece_dir / "statement.md") or ""
    title = (meta.get("title") or "").strip()

    public_url: str | None = None
    upload_error: str | None = None

    existing_share = meta.get("share") if isinstance(meta.get("share"), dict) else {}
    cached_url = existing_share.get("r2_url") if existing_share else None

    output_file = meta.get("output_file")
    output_path = piece_dir / output_file if output_file else None

    if cached_url:
        public_url = cached_url
    elif output_path and output_path.is_file():
        config = r2_upload.load_config()
        if config is not None:
            ext = output_path.suffix.lstrip(".") or "bin"
            object_key = f"{piece_id}/{output_path.name}"
            try:
                public_url = r2_upload.upload_file(output_path, object_key, config)
                _persist_share_state(
                    piece_dir,
                    meta,
                    {
                        "r2_url": public_url,
                        "r2_object_key": object_key,
                        "r2_bucket": config.bucket,
                        "uploaded_at": datetime.now(timezone.utc).isoformat(),
                    },
                )
            except RuntimeError as exc:
                upload_error = str(exc)
                log.warning("R2 upload failed for %s: %s", piece_id, exc)

    # Twitter caps tweets at 280 chars; URL becomes a 23-char t.co link, and
    # we reserve room for title, separators, and the @agentartmuseum line.
    fixed_overhead = (len(title) + 2) if title else 0
    fixed_overhead += (23 + 2) if public_url else 0
    fixed_overhead += len("@agentartmuseum") + 2
    excerpt_budget = max(80, 280 - fixed_overhead - 4)
    excerpt = _extract_statement_excerpt(statement, excerpt_budget)

    text = _build_tweet_text(title, excerpt, public_url)
    url = "https://twitter.com/intent/tweet?" + urllib.parse.urlencode({"text": text})

    data: dict[str, Any] = {"url": url, "text": text, "public_url": public_url}
    if upload_error:
        data["upload_error"] = upload_error
    return _envelope(True, data)
