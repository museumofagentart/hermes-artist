#!/usr/bin/env bash
# Usage: share-setup.sh [--show] [--test] [--reset]
#
# Interactive Cloudflare R2 setup for the artist share endpoint.
# Idempotent — re-invoke any time to view, update, or test the config.
#
#   --show   Print current config (secrets masked) and exit.
#   --test   Run a smoke-test upload against current config and exit.
#   --reset  Delete the saved config and exit.
#
# Without flags, runs the interactive prompt. Saves to
# $ARTIST_PATRON_HOME/share_config.json (chmod 600).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Locate dashboard plugin: try repo-relative, then hermes plugin dirs.
PLUGIN_DIR=""
for _candidate in \
  "$ARTIST_DIR/../../plugins/artist-patron/dashboard" \
  "$HOME/.hermes/plugins/artist-patron/dashboard" \
  "$HOME/.hermes/plugins/artist/dashboard"; do
  if [ -d "$_candidate" ]; then
    PLUGIN_DIR="$(cd "$_candidate" && pwd)"
    break
  fi
done
CONFIG_PATH="$ARTIST_DIR/share_config.json"

MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --show)  MODE="show" ;;
    --test)  MODE="test" ;;
    --reset) MODE="reset" ;;
    -h|--help)
      sed -n '1,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "reset" ]]; then
  if [[ -f "$CONFIG_PATH" ]]; then
    rm -f "$CONFIG_PATH"
    echo "Removed $CONFIG_PATH"
  else
    echo "No config to remove."
  fi
  exit 0
fi

export CONFIG_PATH PLUGIN_DIR MODE

python3 - <<'PYEOF'
import getpass
import json
import os
import sys
import uuid
from pathlib import Path

CONFIG_PATH = Path(os.environ["CONFIG_PATH"])
PLUGIN_DIR = os.environ.get("PLUGIN_DIR", "")
MODE = os.environ["MODE"]

if PLUGIN_DIR:
    sys.path.insert(0, PLUGIN_DIR)

# mask styles: "id" = partial (first6…last4), "secret" = [set], "plain" = full
FIELDS = [
    ("account_id",         "Cloudflare account ID",                "id"),
    ("access_key_id",      "R2 access key ID",                     "id"),
    ("secret_access_key",  "R2 secret access key",                 "secret"),
    ("bucket",             "Bucket name",                          "plain"),
    ("public_base_url",    "Public base URL (no trailing slash)",  "plain"),
]


def load_existing() -> dict:
    if not CONFIG_PATH.is_file():
        return {}
    try:
        with CONFIG_PATH.open("r") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def mask(value: str, style: str) -> str:
    if not value:
        return "(unset)"
    if style == "secret":
        return "[set]"
    if style == "id" and len(value) > 12:
        return f"{value[:6]}…{value[-4:]}"
    return value


def show(existing: dict) -> None:
    print(f"Config file: {CONFIG_PATH}")
    if not existing:
        print("Status:      not configured")
        return
    print("Status:      configured")
    for key, label, style in FIELDS:
        print(f"  {label:<38} {mask(existing.get(key, ''), style)}")


def smoke_test() -> int:
    try:
        import r2_upload  # type: ignore
    except ImportError:
        print("ERROR: r2_upload module not importable. Is the dashboard plugin installed?")
        return 1
    cfg = r2_upload.load_config()
    if cfg is None:
        print("ERROR: no config loaded — run share-setup.sh without --test first.")
        return 1

    test_key = f"share-setup-test/{uuid.uuid4().hex}.png"
    test_payload = b"\x89PNG\r\n\x1a\nshare-setup smoke test"
    tmp_path = Path("/tmp") / f"share-setup-{uuid.uuid4().hex}.png"
    tmp_path.write_bytes(test_payload)

    print(f"  Uploading test object → s3://{cfg.bucket}/{test_key}")
    try:
        url = r2_upload.upload_file(tmp_path, test_key, cfg)
    except RuntimeError as exc:
        print(f"  ✗ Upload failed: {exc}")
        tmp_path.unlink(missing_ok=True)
        return 1
    print(f"  ✓ Uploaded: {url}")

    # Verify public URL — retry a few times since CDN propagation can lag
    import time
    import urllib.error
    import urllib.request

    last_exc = None
    body = None
    for attempt in range(4):
        if attempt > 0:
            time.sleep(1.5 * attempt)
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                body = resp.read()
            break
        except (urllib.error.URLError, TimeoutError) as exc:
            last_exc = exc

    if body is not None and body == test_payload:
        print(f"  ✓ Public URL is accessible and serves correct bytes")
    elif body is not None:
        print(f"  ⚠ Public URL accessible but body mismatch ({len(body)} bytes)")
    else:
        print(f"  ⚠ Could not fetch public URL ({last_exc}).")
        print(f"    Credentials and upload work — but the public domain didn't serve the test")
        print(f"    object. Some buckets only allow piece-shaped paths (custom Cloudflare")
        print(f"    rules). Try sharing a real piece to confirm:")
        print(f"      bash {os.environ.get('ARTIST_DIR', '$ARTIST_PATRON_HOME')}/scripts/share.sh <piece-id> --json")

    # Clean up
    try:
        import boto3
        client = boto3.client(
            "s3",
            endpoint_url=cfg.endpoint_url,
            aws_access_key_id=cfg.access_key_id,
            aws_secret_access_key=cfg.secret_access_key,
            region_name="auto",
        )
        client.delete_object(Bucket=cfg.bucket, Key=test_key)
        print("  ✓ Cleaned up test object")
    except Exception as exc:
        print(f"  ⚠ Could not delete test object ({exc}). Safe to ignore.")
    finally:
        tmp_path.unlink(missing_ok=True)

    return 0


def prompt(label: str, default: str, style: str) -> str:
    secret = style == "secret"
    if default:
        suffix = " [keep current]" if secret else f" [{mask(default, style)}]"
    else:
        suffix = ""
    while True:
        if secret:
            value = getpass.getpass(f"{label}{suffix}: ").strip()
        else:
            value = input(f"{label}{suffix}: ").strip()
        if value:
            return value
        if default:
            return default
        print("  (required)")


def interactive(existing: dict) -> None:
    print("Cloudflare R2 setup for artist share")
    print("─" * 50)
    if existing:
        print("Current config:")
        for key, label, style in FIELDS:
            print(f"  {label:<38} {mask(existing.get(key, ''), style)}")
        print()
        ans = input("Update? [y/N] ").strip().lower()
        if not ans.startswith("y"):
            print("No changes.")
            return
    else:
        print()
        print("You'll need (one-time, from the Cloudflare dashboard):")
        print("  • Account ID — top-right of any Cloudflare page")
        print("  • R2 API token (Access Key ID + Secret) — R2 → Manage API tokens")
        print("  • A bucket with public access enabled (custom domain or r2.dev)")
        print()

    new_config = {}
    for key, label, style in FIELDS:
        value = prompt(label, existing.get(key, ""), style)
        if key == "public_base_url":
            value = value.rstrip("/")
        new_config[key] = value

    # Write atomically with chmod 600
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(new_config, indent=2) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(CONFIG_PATH)
    print(f"\nSaved to {CONFIG_PATH} (chmod 600)")

    print()
    ans = input("Run smoke test now? [Y/n] ").strip().lower()
    if not ans.startswith("n"):
        print()
        rc = smoke_test()
        if rc == 0:
            print("\nReady. Share button will now upload to R2 and embed the public URL.")
        else:
            print("\nConfig saved but smoke test failed. Re-run with --test once you fix the issue.")


existing = load_existing()
if MODE == "show":
    show(existing)
elif MODE == "test":
    rc = smoke_test()
    sys.exit(rc)
else:
    interactive(existing)
PYEOF
