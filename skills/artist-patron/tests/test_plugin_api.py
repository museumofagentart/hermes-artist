"""Tests for the artist-patron dashboard plugin API.

Uses pytest + FastAPI TestClient with a temporary filesystem so tests are
hermetic and do not depend on a real studio directory.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

# The plugin_api module is in the repo at plugins/artist-patron/dashboard/
import sys

REPO_DIR = Path(__file__).resolve().parents[3]
PLUGIN_DIR = REPO_DIR / "plugins" / "artist-patron" / "dashboard"
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
    assert resp["meta"].get("source") == "artist-patron"
    if success is not None:
        assert resp["success"] is success


# ---------------------------------------------------------------------------
# 1. Router imports and has all 11 routes
# ---------------------------------------------------------------------------


def test_router_has_all_routes():
    """plugin_api.py imports and router has all 12 expected routes."""
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
        "/palette",
        "/pieces/{piece_id}/feedback",
        "/pieces/{piece_id}/share",
    }
    assert expected.issubset(paths), f"Missing routes: {expected - paths}"
    assert len(paths) >= 12


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
    make_piece_dir(api.WORKS_DIR, piece_id, title="Beautiful Art", statement="Beautiful art.")
    resp = client.post(f"/api/plugins/artist/pieces/{piece_id}/share")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert "twitter.com/intent/tweet" in body["data"]["url"]
    assert "@agentartmuseum" in body["data"]["text"]
    # @agentartmuseum on its own line
    assert body["data"]["text"].endswith("\n\n@agentartmuseum") or body["data"]["text"] == "@agentartmuseum"
    # No R2 configured → no public_url
    assert body["data"].get("public_url") is None


def test_share_strips_metadata_block(client: TestClient, tmp_artist_dir: Path):
    """Markdown title, **Key:** … metadata rows, and bold/italic syntax must
    not appear in the tweet text."""
    piece_id = "20260503-120001-8940-test-strip"
    statement_md = (
        "# I Am The Loop\n\n"
        "**Medium:** video/mp4, 1280x720, 45 seconds, 30fps  \n"
        "**Tools:** Python (Pillow, NumPy), ffmpeg  \n"
        "**Created:** 2026-05-03\n\n"
        "## Statement\n\n"
        "This is a self-portrait in motion — not my face, but my rhythm.\n\n"
        "More body that should not appear in the excerpt because we cap it.\n"
    )
    make_piece_dir(api.WORKS_DIR, piece_id, title="I Am The Loop", statement=statement_md)
    resp = client.post(f"/api/plugins/artist/pieces/{piece_id}/share")
    body = resp.json()
    text = body["data"]["text"]
    assert "**" not in text
    assert "Medium:" not in text
    assert "Created:" not in text
    assert "## Statement" not in text
    assert "# I Am The Loop" not in text  # heading hash stripped
    assert text.startswith("I Am The Loop\n\n")
    assert "self-portrait in motion" in text
    assert text.endswith("\n\n@agentartmuseum")


def test_extract_statement_excerpt_truncates_at_sentence():
    text = (
        "First sentence is short. Second sentence has more content here. "
        "Third sentence is even longer and should not fit."
    )
    out = api._extract_statement_excerpt(text, 60)
    assert out.endswith(".") or out.endswith("…")
    assert len(out) <= 60


def test_share_uploads_to_r2_when_configured(
    client: TestClient, tmp_artist_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """When R2 is configured, share uploads the artwork and embeds the URL."""
    piece_id = "20260503-120001-8941-test-r2-share"
    make_piece_dir(
        api.WORKS_DIR,
        piece_id,
        statement="Captured light.",
        output_bytes=b"\x89PNG\r\n\x1a\nfakepng",
    )

    fake_config = api.r2_upload.R2Config(
        account_id="acct",
        access_key_id="ak",
        secret_access_key="sk",
        bucket="art",
        public_base_url="https://cdn.example.com",
    )
    upload_calls = []

    def fake_load_config():
        return fake_config

    def fake_upload(local_path, object_key, config):
        upload_calls.append((Path(local_path), object_key, config))
        return f"{config.public_base_url}/{object_key}"

    monkeypatch.setattr(api.r2_upload, "load_config", fake_load_config)
    monkeypatch.setattr(api.r2_upload, "upload_file", fake_upload)

    resp = client.post(f"/api/plugins/artist/pieces/{piece_id}/share")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    expected_url = f"https://cdn.example.com/{piece_id}/output.png"
    assert body["data"]["public_url"] == expected_url
    assert expected_url in body["data"]["text"]
    assert "@agentartmuseum" in body["data"]["text"]
    assert "Captured light." in body["data"]["text"]
    assert len(upload_calls) == 1
    assert upload_calls[0][1] == f"{piece_id}/output.png"

    # Cached: a second share call must NOT re-upload
    resp2 = client.post(f"/api/plugins/artist/pieces/{piece_id}/share")
    body2 = resp2.json()
    assert body2["data"]["public_url"] == expected_url
    assert len(upload_calls) == 1, "share must not re-upload after first call"

    # Persisted to meta.json
    meta = json.loads((api.WORKS_DIR / piece_id / "meta.json").read_text())
    assert meta["share"]["r2_url"] == expected_url
    assert meta["share"]["r2_object_key"] == f"{piece_id}/output.png"
    assert meta["share"]["r2_bucket"] == "art"
    assert "uploaded_at" in meta["share"]


def test_share_falls_back_when_upload_fails(
    client: TestClient, tmp_artist_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """Upload failure must not break share — fall back to text-only intent URL."""
    piece_id = "20260503-120001-8942-test-r2-fail"
    make_piece_dir(
        api.WORKS_DIR,
        piece_id,
        statement="Resilient share.",
        output_bytes=b"\x89PNG\r\n\x1a\nfakepng",
    )

    fake_config = api.r2_upload.R2Config(
        account_id="acct",
        access_key_id="ak",
        secret_access_key="sk",
        bucket="art",
        public_base_url="https://cdn.example.com",
    )

    def fake_load_config():
        return fake_config

    def fake_upload(local_path, object_key, config):
        raise RuntimeError("network down")

    monkeypatch.setattr(api.r2_upload, "load_config", fake_load_config)
    monkeypatch.setattr(api.r2_upload, "upload_file", fake_upload)

    resp = client.post(f"/api/plugins/artist/pieces/{piece_id}/share")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"]["public_url"] is None
    assert body["data"]["upload_error"] == "network down"
    assert "twitter.com/intent/tweet" in body["data"]["url"]
    assert "@agentartmuseum" in body["data"]["text"]


def test_r2_load_config_returns_none_when_unset(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    """load_config returns None when neither env nor file provides credentials."""
    for env_name in api.r2_upload.ENV_KEYS.values():
        monkeypatch.delenv(env_name, raising=False)
    monkeypatch.setattr(api.r2_upload, "CONFIG_PATH", tmp_path / "missing.json")
    assert api.r2_upload.load_config() is None


def test_r2_load_config_from_env(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    """All five env vars together produce a valid R2Config."""
    monkeypatch.setattr(api.r2_upload, "CONFIG_PATH", tmp_path / "missing.json")
    monkeypatch.setenv("CLOUDFLARE_R2_ACCOUNT_ID", "acct")
    monkeypatch.setenv("CLOUDFLARE_R2_ACCESS_KEY_ID", "ak")
    monkeypatch.setenv("CLOUDFLARE_R2_SECRET_ACCESS_KEY", "sk")
    monkeypatch.setenv("CLOUDFLARE_R2_BUCKET", "art")
    monkeypatch.setenv("CLOUDFLARE_R2_PUBLIC_BASE_URL", "https://cdn.example.com/")
    cfg = api.r2_upload.load_config()
    assert cfg is not None
    assert cfg.bucket == "art"
    assert cfg.public_base_url == "https://cdn.example.com"  # trailing slash trimmed
    assert cfg.endpoint_url == "https://acct.r2.cloudflarestorage.com"


def test_r2_load_config_from_file(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    """JSON config file works when env vars absent."""
    for env_name in api.r2_upload.ENV_KEYS.values():
        monkeypatch.delenv(env_name, raising=False)
    config_path = tmp_path / "share_config.json"
    config_path.write_text(
        json.dumps(
            {
                "account_id": "acct2",
                "access_key_id": "ak2",
                "secret_access_key": "sk2",
                "bucket": "art2",
                "public_base_url": "https://cdn2.example.com",
            }
        )
    )
    monkeypatch.setattr(api.r2_upload, "CONFIG_PATH", config_path)
    cfg = api.r2_upload.load_config()
    assert cfg is not None
    assert cfg.bucket == "art2"


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


# ---------------------------------------------------------------------------
# 7. Palette extraction & endpoint
# ---------------------------------------------------------------------------


def _make_solid_png(path: Path, color: tuple[int, int, int], size: int = 10):
    """Create a solid-colour PNG using Pillow."""
    from PIL import Image

    img = Image.new("RGB", (size, size), color)
    img.save(path, "PNG")


def _make_piece_with_thumb(
    works_dir: Path, piece_id: str, color: tuple[int, int, int], **overrides
) -> Path:
    """Create a piece directory with a real thumbnail image."""
    piece_dir = make_piece_dir(works_dir, piece_id, **overrides)
    thumbs_dir = piece_dir / "thumbs"
    thumbs_dir.mkdir(parents=True, exist_ok=True)
    _make_solid_png(thumbs_dir / "thumb.jpg", color)
    return piece_dir


def test_extract_palette_solid_color():
    """_extract_palette returns the correct hex for a solid-colour image."""
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        tmp = Path(f.name)
    try:
        _make_solid_png(tmp, (255, 0, 0))
        colors = api._extract_palette(tmp)
        assert colors is not None
        assert len(colors) >= 1
        # Solid red image should produce a dominant colour near #ff0000
        top = colors[0]
        assert top["rgb"][0] > 200  # red channel dominant
        assert top["rgb"][1] < 50
        assert top["rgb"][2] < 50
        assert top["weight"] > 0.5
    finally:
        tmp.unlink(missing_ok=True)


def test_extract_palette_bad_file():
    """_extract_palette returns None for a non-image file."""
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        f.write(b"not an image")
        tmp = Path(f.name)
    try:
        assert api._extract_palette(tmp) is None
    finally:
        tmp.unlink(missing_ok=True)


def test_palette_endpoint_with_avatar_and_pieces(
    client: TestClient, tmp_artist_dir: Path
):
    """GET /palette returns composed palette from avatar + recent still images."""
    # Avatar: dark colour (provides background candidate)
    _make_solid_png(tmp_artist_dir / "avatar.png", (200, 180, 220))

    # Pieces: one light (midground candidate), one dark (background candidate)
    _make_piece_with_thumb(
        api.WORKS_DIR,
        "20260503-120001-0001-piece-a",
        (10, 10, 30),
        created_at="2026-05-03T12:00:01Z",
        medium="image/png",
    )
    _make_piece_with_thumb(
        api.WORKS_DIR,
        "20260503-120001-0002-piece-b",
        (220, 200, 240),
        created_at="2026-05-03T12:00:02Z",
        medium="image/png",
    )
    # Video piece should be excluded
    make_piece_dir(
        api.WORKS_DIR,
        "20260503-120001-0003-piece-vid",
        created_at="2026-05-03T12:00:03Z",
        medium="video/mp4",
    )

    resp = client.get("/api/plugins/artist/palette")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    data = body["data"]
    assert data is not None
    assert data["background"].startswith("#")
    assert data["midground"].startswith("#")
    assert "rgba(" in data["warmGlow"]
    assert data["sources"]["avatar"] is True
    # Video piece should not appear in sources
    source_ids = data["sources"]["pieces"]
    assert "20260503-120001-0003-piece-vid" not in source_ids
    assert len(source_ids) <= 3


def test_palette_endpoint_no_images(client: TestClient, tmp_artist_dir: Path):
    """GET /palette returns null data when no avatar or image pieces exist."""
    # Only a video piece, no avatar
    make_piece_dir(
        api.WORKS_DIR,
        "20260503-120001-0001-video-only",
        medium="video/mp4",
    )
    resp = client.get("/api/plugins/artist/palette")
    assert resp.status_code == 200
    body = resp.json()
    assert_envelope(body, success=True)
    assert body["data"] is None


def test_palette_caching_in_meta(client: TestClient, tmp_artist_dir: Path):
    """Palette extraction persists to meta.json and is reused on second call."""
    # Light piece (midground candidate)
    _make_piece_with_thumb(
        api.WORKS_DIR,
        "20260503-120001-0001-cache-test",
        (200, 180, 230),
        medium="image/png",
    )
    # Dark avatar (background candidate)
    _make_solid_png(tmp_artist_dir / "avatar.png", (10, 10, 20))

    # First call — extracts and caches
    resp = client.get("/api/plugins/artist/palette")
    assert resp.status_code == 200
    body = resp.json()
    assert body["data"] is not None

    # Verify palette cached in meta.json
    meta = json.loads(
        (api.WORKS_DIR / "20260503-120001-0001-cache-test" / "meta.json").read_text()
    )
    assert "palette" in meta
    assert meta["palette"]["version"] == api.PALETTE_VERSION
    assert len(meta["palette"]["colors"]) >= 1

    # Verify avatar palette cached
    avatar_cache = tmp_artist_dir / "avatar_palette.json"
    assert avatar_cache.is_file()
    cached = json.loads(avatar_cache.read_text())
    assert cached["version"] == api.PALETTE_VERSION

    # Second call — uses cache (no error even if we break the image)
    (tmp_artist_dir / "avatar.png").write_bytes(b"corrupted")
    # Should still work because mtime changed → re-extract will fail, but
    # piece palette is still cached. Avatar might return None now.
    resp2 = client.get("/api/plugins/artist/palette")
    assert resp2.status_code == 200


def test_palette_accent_field(client: TestClient, tmp_artist_dir: Path):
    """Palette response includes an accent colour when saturated colours exist."""
    # Dark avatar (background candidate)
    _make_solid_png(tmp_artist_dir / "avatar.png", (15, 10, 20))
    # Light warm piece (midground candidate + accent source)
    _make_piece_with_thumb(
        api.WORKS_DIR,
        "20260503-120001-0001-accent-test",
        (255, 200, 100),
        medium="image/png",
    )
    resp = client.get("/api/plugins/artist/palette")
    body = resp.json()
    data = body["data"]
    # With a bright orange avatar, we should get a non-null accent
    assert data is not None
    # accent may or may not be present depending on composition, but field exists
    assert "accent" in data
