"""Tests for the artist dashboard plugin API.

Uses pytest + FastAPI TestClient with a temporary filesystem so tests are
hermetic and do not depend on the real ~/.hermes/artist/ directory.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

# The plugin_api module is in the repo at plugins/artist/dashboard/
import sys

REPO_DIR = Path(__file__).resolve().parents[2]
PLUGIN_DIR = REPO_DIR / "plugins" / "artist" / "dashboard"
sys.path.insert(0, str(PLUGIN_DIR))

import plugin_api as api


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def app() -> FastAPI:
    """FastAPI app with the artist plugin router mounted."""
    fast_app = FastAPI()
    fast_app.include_router(api.router, prefix="/api/plugins/artist")
    return fast_app


@pytest.fixture
def client(app: FastAPI) -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def tmp_artist_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Redirect ARTIST_DIR and WORKS_DIR to a temp directory for every test."""
    artist_dir = tmp_path / "artist"
    works_dir = artist_dir / "works"
    artist_dir.mkdir(parents=True)
    works_dir.mkdir(parents=True)
    monkeypatch.setattr(api, "ARTIST_DIR", artist_dir)
    monkeypatch.setattr(api, "WORKS_DIR", works_dir)
    return artist_dir


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_piece_dir(works_dir: Path, piece_id: str, **overrides) -> Path:
    """Create a minimal piece directory with meta.json and optional files."""
    piece_dir = works_dir / piece_id
    piece_dir.mkdir(parents=True)
    meta = {
        "schema_version": "1",
        "id": piece_id,
        "title": overrides.get("title", "Test Piece"),
        "created_at": overrides.get("created_at", "2026-05-03T12:00:00.000000Z"),
        "seed": "test seed",
        "medium": overrides.get("medium", "image/png"),
        "output_file": "output.png",
        "tools_used": ["pillow"],
        "revision_of": None,
        "references": [],
        "patron_feedback": overrides.get(
            "patron_feedback",
            {
                "favorite": False,
                "favorite_at": None,
                "discouraged": False,
                "discouraged_at": None,
                "comments": [],
            },
        ),
    }
    file_content_keys = {"statement", "process", "output_bytes", "thumb_bytes", "review_bytes"}
    meta.update({k: v for k, v in overrides.items() if k not in meta and k not in file_content_keys})
    (piece_dir / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    if "statement" in overrides:
        (piece_dir / "statement.md").write_text(overrides["statement"], encoding="utf-8")
    if "process" in overrides:
        (piece_dir / "process.md").write_text(overrides["process"], encoding="utf-8")
    if "output_bytes" in overrides:
        (piece_dir / "output.png").write_bytes(overrides["output_bytes"])
    if "thumb_bytes" in overrides:
        thumbs_dir = piece_dir / "thumbs"
        thumbs_dir.mkdir(parents=True)
        (thumbs_dir / "thumb.jpg").write_bytes(overrides["thumb_bytes"])
    if "review_bytes" in overrides:
        thumbs_dir = piece_dir / "thumbs"
        thumbs_dir.mkdir(parents=True)
        (thumbs_dir / "review.jpg").write_bytes(overrides["review_bytes"])
    return piece_dir


def assert_envelope(resp: dict, success: bool = True):
    """Assert that a JSON response follows the standard envelope."""
    assert "success" in resp
    assert "data" in resp
    assert "meta" in resp
    assert isinstance(resp["meta"], dict)
    assert resp["meta"].get("source") == "artist"
    if success is not None:
        assert resp["success"] is success


# ---------------------------------------------------------------------------
# 1. Router imports and has all 11 routes
# ---------------------------------------------------------------------------


def test_router_has_all_routes():
    """plugin_api.py imports and router has all 11 expected routes."""
    paths = {route.path for route in api.router.routes}
    expected = {
        "/avatar",
        "/identity",
        "/gallery",
        "/pieces/{piece_id}",
        "/pieces/{piece_id}/output",
        "/pieces/{piece_id}/thumb",
        "/review",
        "/studio",
        "/perspective",
        "/pieces/{piece_id}/feedback",
        "/pieces/{piece_id}/share",
    }
    assert expected.issubset(paths), f"Missing routes: {expected - paths}"
    assert len(paths) >= 11


# ---------------------------------------------------------------------------
# 2. piece_id validation rejects path traversal
# ---------------------------------------------------------------------------


def test_validate_piece_id_rejects_traversal():
    """piece_id validation function rejects path traversal attempts."""
    from fastapi import HTTPException

    bad_ids = [
        "../etc/passwd",
        "20260503-120001-8939-self/../../../etc/passwd",
        "foo/bar",
        "foo%2fbar",
        "foo%2e%2ebar",
        "",
        "invalid",
        "20260503-120001-8939-self portrait",  # space not allowed
    ]
    for bad_id in bad_ids:
        with pytest.raises(HTTPException) as exc_info:
            api._validate_piece_id(bad_id)
        assert exc_info.value.status_code == 400
        detail = exc_info.value.detail
        assert isinstance(detail, dict)
        assert detail["success"] is False


def test_validate_piece_id_accepts_valid():
    """Valid piece IDs resolve to the expected directory."""
    valid_id = "20260503-120001-8939-self-portrait"
    result = api._validate_piece_id(valid_id)
    assert result == api.WORKS_DIR / valid_id


# ---------------------------------------------------------------------------
# 3. Envelope format of each route (mock filesystem)
# ---------------------------------------------------------------------------


def test_avatar_missing(client: TestClient, tmp_artist_dir: Path):
    resp = client.get("/api/plugins/artist/avatar")
    assert resp.status_code == 404
    body = resp.json()
    assert_envelope(body, success=False)


def test_avatar_present(client: TestClient, tmp_artist_dir: Path):
    avatar = tmp_artist_dir / "avatar.png"
    avatar.write_bytes(b"\x89PNG\r\n\x1a\n")
    resp = client.get("/api/plugins/artist/avatar")
    assert resp.status_code == 200
    assert resp.content == b"\x89PNG\r\n\x1a\n"


def test_identity(client: TestClient, tmp_artist_dir: Path):
    perspective = tmp_artist_dir / "PERSPECTIVE.md"
    perspective.write_text("# Perspective\n\nTest content.", encoding="utf-8")
    resp = client.get("/api/plugins/artist/identity")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["perspective"] == "# Perspective\n\nTest content."
    assert body["data"]["avatar_exists"] is False


def test_gallery_empty(client: TestClient):
    resp = client.get("/api/plugins/artist/gallery")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"] == []
    assert body["meta"]["total"] == 0


def test_piece_detail(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-piece"
    make_piece_dir(
        api.WORKS_DIR,
        piece_id,
        title="My Piece",
        statement="# Statement\nArt.",
        process="# Process\nCode.",
    )
    resp = client.get(f"/api/plugins/artist/pieces/{piece_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["meta"]["title"] == "My Piece"
    assert body["data"]["statement"] == "# Statement\nArt."
    assert body["data"]["process"] == "# Process\nCode."


def test_piece_detail_not_found(client: TestClient):
    resp = client.get("/api/plugins/artist/pieces/20260503-120001-8939-nonexistent")
    assert resp.status_code == 404
    body = resp.json()
    assert_envelope(body, success=False)


def test_output_file(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-output"
    make_piece_dir(
        api.WORKS_DIR,
        piece_id,
        output_bytes=b"fake-image",
    )
    resp = client.get(f"/api/plugins/artist/pieces/{piece_id}/output")
    assert resp.status_code == 200
    assert resp.content == b"fake-image"


def test_output_file_missing(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-output-missing"
    make_piece_dir(api.WORKS_DIR, piece_id)
    resp = client.get(f"/api/plugins/artist/pieces/{piece_id}/output")
    assert resp.status_code == 404
    body = resp.json()
    assert_envelope(body, success=False)


def test_thumb_file(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-thumb"
    make_piece_dir(api.WORKS_DIR, piece_id, thumb_bytes=b"fake-thumb")
    resp = client.get(f"/api/plugins/artist/pieces/{piece_id}/thumb")
    assert resp.status_code == 200
    assert resp.content == b"fake-thumb"


def test_thumb_file_missing(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-thumb-missing"
    make_piece_dir(api.WORKS_DIR, piece_id)
    resp = client.get(f"/api/plugins/artist/pieces/{piece_id}/thumb")
    assert resp.status_code == 404
    body = resp.json()
    assert_envelope(body, success=False)


def test_review_default(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-review"
    make_piece_dir(api.WORKS_DIR, piece_id, review_bytes=b"fake-review")
    resp = client.get("/api/plugins/artist/review")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert len(body["data"]) == 1
    assert body["data"][0]["id"] == piece_id


def test_review_by_id(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-review-id"
    make_piece_dir(api.WORKS_DIR, piece_id)
    resp = client.get(f"/api/plugins/artist/review?piece_id={piece_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert len(body["data"]) == 1
    assert body["data"][0]["id"] == piece_id


def test_studio(client: TestClient, tmp_artist_dir: Path):
    studio = tmp_artist_dir / "studio.json"
    studio.write_text(json.dumps({"setup_completed": True}), encoding="utf-8")
    resp = client.get("/api/plugins/artist/studio")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["setup_completed"] is True


def test_studio_missing(client: TestClient):
    resp = client.get("/api/plugins/artist/studio")
    assert resp.status_code == 404
    body = resp.json()
    assert_envelope(body, success=False)


def test_perspective(client: TestClient, tmp_artist_dir: Path):
    perspective = tmp_artist_dir / "PERSPECTIVE.md"
    perspective.write_text("# Aesthetic\nTest.", encoding="utf-8")
    resp = client.get("/api/plugins/artist/perspective")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["content"] == "# Aesthetic\nTest."


def test_perspective_missing(client: TestClient):
    resp = client.get("/api/plugins/artist/perspective")
    assert resp.status_code == 404
    body = resp.json()
    assert_envelope(body, success=False)


def test_share(client: TestClient, tmp_artist_dir: Path):
    piece_id = "20260503-120001-8939-test-share"
    make_piece_dir(api.WORKS_DIR, piece_id, statement="Beautiful art.")
    resp = client.post(f"/api/plugins/artist/pieces/{piece_id}/share")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert "twitter.com/intent/tweet" in body["data"]["url"]
    assert "@agentartmuseum" in body["data"]["text"]


# ---------------------------------------------------------------------------
# 4. /gallery pagination logic
# ---------------------------------------------------------------------------


def test_gallery_pagination(client: TestClient, tmp_artist_dir: Path):
    """Gallery supports limit, offset, and favorites filter."""
    for i in range(5):
        make_piece_dir(
            api.WORKS_DIR,
            f"20260503-120001-000{i}-piece-{i}",
            created_at=f"2026-05-03T12:00:0{i}.000000Z",
            patron_feedback={
                "favorite": i % 2 == 0,
                "favorite_at": "2026-05-03T12:00:00Z" if i % 2 == 0 else None,
                "discouraged": False,
                "discouraged_at": None,
                "comments": [],
            },
        )

    # Default limit=20 returns all 5
    resp = client.get("/api/plugins/artist/gallery")
    body = resp.json()
    assert body["meta"]["total"] == 5
    assert len(body["data"]) == 5

    # limit=2, offset=0 returns first 2 (newest first)
    resp = client.get("/api/plugins/artist/gallery?limit=2&offset=0")
    body = resp.json()
    assert len(body["data"]) == 2
    assert body["meta"]["total"] == 5
    assert body["data"][0]["id"] == "20260503-120001-0004-piece-4"
    assert body["data"][1]["id"] == "20260503-120001-0003-piece-3"

    # limit=2, offset=2 returns next 2
    resp = client.get("/api/plugins/artist/gallery?limit=2&offset=2")
    body = resp.json()
    assert len(body["data"]) == 2
    assert body["data"][0]["id"] == "20260503-120001-0002-piece-2"
    assert body["data"][1]["id"] == "20260503-120001-0001-piece-1"

    # offset beyond total returns empty
    resp = client.get("/api/plugins/artist/gallery?limit=10&offset=10")
    body = resp.json()
    assert len(body["data"]) == 0
    assert body["meta"]["total"] == 5


def test_gallery_favorites_filter(client: TestClient, tmp_artist_dir: Path):
    """Gallery favorites=true returns only favorited pieces."""
    make_piece_dir(
        api.WORKS_DIR,
        "20260503-120001-0000-fav",
        created_at="2026-05-03T12:00:00.000000Z",
        patron_feedback={
            "favorite": True,
            "favorite_at": "2026-05-03T12:00:00Z",
            "discouraged": False,
            "discouraged_at": None,
            "comments": [],
        },
    )
    make_piece_dir(
        api.WORKS_DIR,
        "20260503-120001-0001-nofav",
        created_at="2026-05-03T12:00:01.000000Z",
        patron_feedback={
            "favorite": False,
            "favorite_at": None,
            "discouraged": False,
            "discouraged_at": None,
            "comments": [],
        },
    )

    resp = client.get("/api/plugins/artist/gallery?favorites=true")
    body = resp.json()
    assert body["meta"]["total"] == 1
    assert body["data"][0]["id"] == "20260503-120001-0000-fav"


def test_gallery_sort_order(client: TestClient, tmp_artist_dir: Path):
    """Gallery sorts by created_at descending (newest first)."""
    make_piece_dir(
        api.WORKS_DIR,
        "20260503-120001-0000-old",
        created_at="2026-05-01T10:00:00.000000Z",
    )
    make_piece_dir(
        api.WORKS_DIR,
        "20260503-120001-0001-new",
        created_at="2026-05-03T10:00:00.000000Z",
    )

    resp = client.get("/api/plugins/artist/gallery")
    body = resp.json()
    assert body["data"][0]["id"] == "20260503-120001-0001-new"
    assert body["data"][1]["id"] == "20260503-120001-0000-old"


# ---------------------------------------------------------------------------
# 5. /feedback action enum validation
# ---------------------------------------------------------------------------


def test_feedback_action_enum(client: TestClient, tmp_artist_dir: Path):
    """Feedback rejects invalid actions and accepts valid ones."""
    piece_id = "20260503-120001-8939-feedback-test"
    make_piece_dir(api.WORKS_DIR, piece_id)

    # Invalid action
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "destroy", "comment": None},
    )
    assert resp.status_code == 422  # Pydantic validation error

    # Valid favorite action
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "favorite"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["favorite"] is True

    # Valid unfavorite action
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "unfavorite"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["data"]["favorite"] is False

    # Valid discourage action
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "discourage"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["data"]["discouraged"] is True

    # Comment action without text should fail
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "comment"},
    )
    assert resp.status_code == 400
    body = resp.json()
    assert_envelope(body, success=False)

    # Comment action with text should succeed
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "comment", "comment": "Lovely work."},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert len(body["data"]["comments"]) == 1
    assert body["data"]["comments"][0]["text"] == "Lovely work."


def test_feedback_comment_validation(client: TestClient, tmp_artist_dir: Path):
    """Feedback rejects control characters and overly long comments."""
    piece_id = "20260503-120001-8939-comment-test"
    make_piece_dir(api.WORKS_DIR, piece_id)

    # Control character (bell \x07)
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "comment", "comment": "Nice\x07work"},
    )
    assert resp.status_code == 400
    body = resp.json()
    assert_envelope(body, success=False)
    assert "control" in body["meta"]["error"].lower()

    # Newline and tab are allowed
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "comment", "comment": "Line one\nLine two\tIndented"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["comments"][0]["text"] == "Line one\nLine two\tIndented"

    # Too long
    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "comment", "comment": "x" * 2001},
    )
    assert resp.status_code == 400
    body = resp.json()
    assert_envelope(body, success=False)
    assert "exceeds" in body["meta"]["error"].lower()


def test_feedback_persists_to_meta_json(client: TestClient, tmp_artist_dir: Path):
    """Feedback writes updated meta.json to disk."""
    piece_id = "20260503-120001-8939-persist-test"
    make_piece_dir(api.WORKS_DIR, piece_id)

    resp = client.post(
        f"/api/plugins/artist/pieces/{piece_id}/feedback",
        json={"action": "favorite"},
    )
    assert resp.status_code == 200

    meta_path = api.WORKS_DIR / piece_id / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    assert meta["patron_feedback"]["favorite"] is True
    assert meta["patron_feedback"]["favorite_at"] is not None
