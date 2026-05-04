"""Tests at the seam between hermes skill discovery and the artist-patron skill.

These tests verify that the skill's structure conforms to hermes's discovery
contract WITHOUT importing hermes itself. They inline the parsing logic from
hermes's skill_utils.parse_frontmatter so we test the same code path.

Run: pytest skills/artist-patron/tests/test_discovery.py -v
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, Tuple

import pytest
import yaml

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SKILL_DIR = Path(__file__).resolve().parent.parent
REPO_DIR = SKILL_DIR.parent.parent
SKILL_MD = SKILL_DIR / "SKILL.md"
PLUGIN_DIR = REPO_DIR / "plugins" / "artist-patron" / "dashboard"


# ---------------------------------------------------------------------------
# Inline hermes's frontmatter parser (same logic as skill_utils.py)
# ---------------------------------------------------------------------------


def parse_frontmatter(content: str) -> Tuple[Dict[str, Any], str]:
    """Exact replica of hermes agent/skill_utils.py:parse_frontmatter."""
    frontmatter: Dict[str, Any] = {}
    body = content

    if not content.startswith("---"):
        return frontmatter, body

    end_match = re.search(r"\n---\s*\n", content[3:])
    if not end_match:
        return frontmatter, body

    yaml_content = content[3 : end_match.start() + 3]
    body = content[end_match.end() + 3 :]

    loader = getattr(yaml, "CSafeLoader", None) or yaml.SafeLoader
    try:
        parsed = yaml.load(yaml_content, Loader=loader)
        if isinstance(parsed, dict):
            frontmatter = parsed
    except Exception:
        for line in yaml_content.strip().split("\n"):
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            frontmatter[key.strip()] = value.strip()

    return frontmatter, body


# ---------------------------------------------------------------------------
# 1. Skill structure conforms to hermes discovery contract
# ---------------------------------------------------------------------------


class TestSkillStructure:
    """Verify the on-disk layout matches what hermes's skill scanner expects."""

    def test_skill_md_exists(self):
        assert SKILL_MD.is_file(), "SKILL.md must exist at the skill root"

    def test_directory_name_matches_frontmatter_name(self):
        fm, _ = parse_frontmatter(SKILL_MD.read_text())
        assert fm["name"] == SKILL_DIR.name, (
            f"Frontmatter name '{fm['name']}' must match directory name '{SKILL_DIR.name}'"
        )

    def test_scripts_directory_exists(self):
        assert (SKILL_DIR / "scripts").is_dir()

    def test_all_scripts_executable(self):
        scripts_dir = SKILL_DIR / "scripts"
        for sh in scripts_dir.glob("*.sh"):
            mode = sh.stat().st_mode
            assert mode & stat.S_IXUSR, f"{sh.name} must be executable"

    def test_works_directory_exists_or_creatable(self):
        works = SKILL_DIR / "works"
        # Either exists or parent is writable (agent creates it at runtime)
        assert works.exists() or os.access(SKILL_DIR, os.W_OK)


# ---------------------------------------------------------------------------
# 2. Frontmatter parses correctly via hermes's parser
# ---------------------------------------------------------------------------


class TestFrontmatter:
    """Verify SKILL.md frontmatter satisfies hermes's required fields."""

    @pytest.fixture
    def frontmatter(self) -> Dict[str, Any]:
        fm, _ = parse_frontmatter(SKILL_MD.read_text())
        return fm

    def test_name_is_artist_patron(self, frontmatter):
        assert frontmatter["name"] == "artist-patron"

    def test_description_present_and_under_limit(self, frontmatter):
        desc = frontmatter["description"]
        assert isinstance(desc, str)
        assert len(desc) > 0
        assert len(desc) <= 1024, "hermes enforces max 1024 char description"

    def test_version_present(self, frontmatter):
        assert "version" in frontmatter

    def test_metadata_tags(self, frontmatter):
        tags = frontmatter.get("metadata", {}).get("hermes", {}).get("tags", [])
        assert isinstance(tags, list)
        assert len(tags) > 0

    def test_requires_toolsets(self, frontmatter):
        toolsets = frontmatter.get("metadata", {}).get("hermes", {}).get("requires_toolsets", [])
        assert "terminal" in toolsets

    def test_setup_declares_artist_patron_home(self, frontmatter):
        secrets = frontmatter.get("setup", {}).get("collect_secrets", [])
        env_names = [s["name"] for s in secrets]
        assert "ARTIST_PATRON_HOME" in env_names, (
            "setup.collect_secrets must declare ARTIST_PATRON_HOME"
        )

    def test_setup_artist_patron_home_not_secret(self, frontmatter):
        secrets = frontmatter.get("setup", {}).get("collect_secrets", [])
        for s in secrets:
            if s["name"] == "ARTIST_PATRON_HOME":
                assert s.get("secret") is False, "ARTIST_PATRON_HOME should not be marked secret"


# ---------------------------------------------------------------------------
# 3. Scripts self-locate regardless of install path
# ---------------------------------------------------------------------------


class TestScriptSelfLocation:
    """Verify scripts derive correct paths from their own location,
    independent of symlinks or env vars."""

    def test_helpers_resolves_artist_dir(self):
        """helpers.sh must set ARTIST_DIR to the skill root via SCRIPT_DIR/..."""
        result = subprocess.run(
            ["bash", "-c", f"source {SKILL_DIR}/scripts/helpers.sh && echo $ARTIST_DIR"],
            capture_output=True, text=True, timeout=5,
            env={**os.environ, "ARTIST_PATRON_HOME": ""},  # clear env var
        )
        assert result.returncode == 0
        resolved = Path(result.stdout.strip()).resolve()
        assert resolved == SKILL_DIR.resolve()

    def test_helpers_resolves_works_dir(self):
        result = subprocess.run(
            ["bash", "-c", f"source {SKILL_DIR}/scripts/helpers.sh && echo $WORKS_DIR"],
            capture_output=True, text=True, timeout=5,
            env={**os.environ, "ARTIST_PATRON_HOME": ""},
        )
        assert result.returncode == 0
        resolved = Path(result.stdout.strip()).resolve()
        assert resolved == (SKILL_DIR / "works").resolve()

    def test_helpers_respects_env_override(self):
        """When ARTIST_PATRON_HOME is set, helpers.sh should use it."""
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                ["bash", "-c", f"source {SKILL_DIR}/scripts/helpers.sh && echo $ARTIST_DIR"],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, "ARTIST_PATRON_HOME": tmp},
            )
            assert result.returncode == 0
            assert result.stdout.strip() == tmp

    def test_scripts_work_from_symlinked_location(self):
        """Simulate hermes's ~/.hermes/skills/artist-patron symlink."""
        with tempfile.TemporaryDirectory() as tmp:
            link = Path(tmp) / "artist-patron"
            link.symlink_to(SKILL_DIR)
            result = subprocess.run(
                ["bash", "-c", f"source {link}/scripts/helpers.sh && echo $ARTIST_DIR"],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, "ARTIST_PATRON_HOME": ""},
            )
            assert result.returncode == 0
            # Should resolve to the real path, not the symlink
            resolved = Path(result.stdout.strip()).resolve()
            assert resolved == SKILL_DIR.resolve()

    def test_generate_id_runs(self):
        """generate-id.sh should produce a valid ID."""
        result = subprocess.run(
            ["bash", f"{SKILL_DIR}/scripts/generate-id.sh", "test-slug", "--json"],
            capture_output=True, text=True, timeout=5,
        )
        assert result.returncode == 0
        envelope = json.loads(result.stdout)
        assert envelope["success"] is True
        assert "test-slug" in envelope["data"]


# ---------------------------------------------------------------------------
# 4. Plugin can resolve studio from env var
# ---------------------------------------------------------------------------


class TestPluginResolution:
    """Verify the dashboard plugin reads ARTIST_PATRON_HOME correctly."""

    def test_plugin_api_resolve_with_env(self, monkeypatch, tmp_path):
        """_resolve_artist_dir should use ARTIST_PATRON_HOME when set."""
        monkeypatch.setenv("ARTIST_PATRON_HOME", str(tmp_path))
        # Re-import to pick up env change
        sys.path.insert(0, str(PLUGIN_DIR))
        import importlib
        import plugin_api
        importlib.reload(plugin_api)
        resolved = plugin_api._resolve_artist_dir()
        assert resolved == tmp_path

    def test_plugin_api_fallback_without_env(self, monkeypatch):
        """Without ARTIST_PATRON_HOME, falls back to ~/.hermes/artist."""
        monkeypatch.delenv("ARTIST_PATRON_HOME", raising=False)
        sys.path.insert(0, str(PLUGIN_DIR))
        import importlib
        import plugin_api
        importlib.reload(plugin_api)
        resolved = plugin_api._resolve_artist_dir()
        assert resolved == Path.home() / ".hermes" / "artist"

    def test_r2_config_path_with_env(self, monkeypatch, tmp_path):
        """r2_upload should look for share_config.json under ARTIST_PATRON_HOME."""
        monkeypatch.setenv("ARTIST_PATRON_HOME", str(tmp_path))
        sys.path.insert(0, str(PLUGIN_DIR))
        import importlib
        import r2_upload
        importlib.reload(r2_upload)
        assert r2_upload._resolve_config_path() == tmp_path / "share_config.json"


# ---------------------------------------------------------------------------
# 5. No dangling references to old paths
# ---------------------------------------------------------------------------


class TestNoDanglingPaths:
    """Ensure the rename is complete -- no references to old hardcoded paths."""

    OLD_PATH_PATTERN = re.compile(r"~/\.hermes/artist(?!/)")

    def _scan_file(self, path: Path) -> list[tuple[int, str]]:
        """Return (line_num, line) tuples matching the old path pattern."""
        hits = []
        try:
            text = path.read_text(errors="replace")
        except (OSError, UnicodeDecodeError):
            return hits
        for i, line in enumerate(text.splitlines(), 1):
            if self.OLD_PATH_PATTERN.search(line):
                # Allow backward-compat comments
                if "backward compat" in line.lower() or "legacy" in line.lower() or "fallback" in line.lower() or "falls back" in line.lower():
                    continue
                hits.append((i, line.strip()))
        return hits

    def test_no_old_paths_in_skill(self):
        hits = []
        for f in SKILL_DIR.rglob("*"):
            if f.is_file() and not f.suffix in (".png", ".jpg", ".pyc", ".mp4", ".wav"):
                hits.extend((str(f), ln, line) for ln, line in self._scan_file(f))
        assert hits == [], f"Old path references found:\n" + "\n".join(
            f"  {f}:{ln}: {line}" for f, ln, line in hits
        )

    def test_no_old_paths_in_plugin(self):
        hits = []
        for f in PLUGIN_DIR.rglob("*"):
            if f.is_file() and f.suffix in (".py", ".json", ".md"):
                hits.extend((str(f), ln, line) for ln, line in self._scan_file(f))
        assert hits == [], f"Old path references found:\n" + "\n".join(
            f"  {f}:{ln}: {line}" for f, ln, line in hits
        )

    def test_no_old_paths_in_setup(self):
        setup = REPO_DIR / "setup.sh"
        if setup.is_file():
            hits = self._scan_file(setup)
            assert hits == [], f"Old path references in setup.sh:\n" + "\n".join(
                f"  {ln}: {line}" for ln, line in hits
            )


# ---------------------------------------------------------------------------
# 6. Envelope source tags are consistent
# ---------------------------------------------------------------------------


class TestEnvelopeSource:
    """All JSON envelopes should use 'artist-patron' as the source tag."""

    def test_envelope_helper_uses_new_source(self):
        result = subprocess.run(
            ["bash", "-c", f'source {SKILL_DIR}/scripts/helpers.sh && envelope_error "test"'],
            capture_output=True, text=True, timeout=5,
        )
        envelope = json.loads(result.stdout)
        assert envelope["meta"]["source"] == "artist-patron"


# ---------------------------------------------------------------------------
# 7. Plugin manifest is valid
# ---------------------------------------------------------------------------


class TestPluginManifest:
    """Verify the dashboard plugin manifest is well-formed."""

    @pytest.fixture
    def manifest(self) -> dict:
        return json.loads((PLUGIN_DIR / "manifest.json").read_text())

    def test_name_matches(self, manifest):
        assert manifest["name"] == "artist-patron"

    def test_required_fields(self, manifest):
        for field in ("name", "label", "entry", "api"):
            assert field in manifest, f"manifest.json missing required field: {field}"

    def test_entry_file_exists(self, manifest):
        entry = PLUGIN_DIR / manifest["entry"]
        assert entry.is_file(), f"Entry file {manifest['entry']} not found"

    def test_api_file_exists(self, manifest):
        api = PLUGIN_DIR / manifest["api"]
        assert api.is_file(), f"API file {manifest['api']} not found"
