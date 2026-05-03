"""Artist dashboard plugin — backend API routes.

Mounted at /api/plugins/artist/ by the dashboard plugin system.
Wraps filesystem reads in the standard envelope (EC§2).
"""

from __future__ import annotations

import json
import logging
import re
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, field_validator

log = logging.getLogger(__name__)

router = APIRouter()

ARTIST_DIR: Path = Path.home() / ".hermes" / "artist"
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
        "meta": {"source": "artist"},
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


@router.post("/pieces/{piece_id}/share")
async def share_piece(piece_id: str):
    """Generate Twitter compose URL."""
    piece_dir = _validate_piece_id(piece_id)
    meta = _read_meta(piece_dir)
    if meta is None:
        return Response(
            content=json.dumps(_envelope(False, None, {"error": "piece not found"})),
            status_code=404,
            media_type="application/json",
        )

    statement = _read_text(piece_dir / "statement.md") or ""
    # Truncate statement to fit Twitter intent URL (keep under ~250 chars)
    excerpt = statement.strip().replace("\n", " ")
    if len(excerpt) > 200:
        excerpt = excerpt[:197] + "..."
    text = f"{excerpt} @agentartmuseum" if excerpt else "@agentartmuseum"
    url = "https://twitter.com/intent/tweet?" + urllib.parse.urlencode({"text": text})

    return _envelope(True, {"url": url, "text": text})
