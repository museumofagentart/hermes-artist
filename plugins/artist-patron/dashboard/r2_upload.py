"""Cloudflare R2 upload helper for the artist-patron share endpoint.

Reads config from env vars or $ARTIST_PATRON_HOME/share_config.json.
Uploads a local file to R2 and returns the public URL, or None if
R2 is not configured. All errors are surfaced as RuntimeError so the
caller can decide whether to fall back to text-only sharing.
"""

from __future__ import annotations

import json
import logging
import mimetypes
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


def _resolve_config_path() -> Path:
    """Resolve share_config.json from ARTIST_PATRON_HOME or legacy path."""
    env = os.environ.get("ARTIST_PATRON_HOME")
    if env:
        return Path(env) / "share_config.json"
    return Path.home() / ".hermes" / "artist" / "share_config.json"


CONFIG_PATH = _resolve_config_path()

ENV_KEYS = {
    "account_id": "CLOUDFLARE_R2_ACCOUNT_ID",
    "access_key_id": "CLOUDFLARE_R2_ACCESS_KEY_ID",
    "secret_access_key": "CLOUDFLARE_R2_SECRET_ACCESS_KEY",
    "bucket": "CLOUDFLARE_R2_BUCKET",
    "public_base_url": "CLOUDFLARE_R2_PUBLIC_BASE_URL",
}


@dataclass(frozen=True)
class R2Config:
    account_id: str
    access_key_id: str
    secret_access_key: str
    bucket: str
    public_base_url: str

    @property
    def endpoint_url(self) -> str:
        return f"https://{self.account_id}.r2.cloudflarestorage.com"


def load_config() -> Optional[R2Config]:
    """Return R2Config if all required fields are present, else None.

    Env vars take precedence over the JSON file.
    """
    values: dict[str, str] = {}
    if CONFIG_PATH.is_file():
        try:
            with CONFIG_PATH.open("r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                for key in ENV_KEYS:
                    v = data.get(key)
                    if isinstance(v, str) and v.strip():
                        values[key] = v.strip()
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("Could not read %s: %s", CONFIG_PATH, exc)

    for key, env_name in ENV_KEYS.items():
        env_v = os.environ.get(env_name, "").strip()
        if env_v:
            values[key] = env_v

    if not all(k in values for k in ENV_KEYS):
        return None

    public_base = values["public_base_url"].rstrip("/")
    return R2Config(
        account_id=values["account_id"],
        access_key_id=values["access_key_id"],
        secret_access_key=values["secret_access_key"],
        bucket=values["bucket"],
        public_base_url=public_base,
    )


def upload_file(local_path: Path, object_key: str, config: R2Config) -> str:
    """Upload a file to R2 and return its public URL.

    Raises RuntimeError on any failure (missing boto3, network, auth, etc.).
    """
    try:
        import boto3
        from botocore.config import Config as BotoConfig
        from botocore.exceptions import BotoCoreError, ClientError
    except ImportError as exc:
        raise RuntimeError(
            "boto3 is required for R2 uploads — install with `pip install boto3`"
        ) from exc

    if not local_path.is_file():
        raise RuntimeError(f"file not found: {local_path}")

    content_type = mimetypes.guess_type(str(local_path))[0] or "application/octet-stream"

    client = boto3.client(
        "s3",
        endpoint_url=config.endpoint_url,
        aws_access_key_id=config.access_key_id,
        aws_secret_access_key=config.secret_access_key,
        region_name="auto",
        config=BotoConfig(signature_version="s3v4", retries={"max_attempts": 3}),
    )

    try:
        client.upload_file(
            str(local_path),
            config.bucket,
            object_key,
            ExtraArgs={"ContentType": content_type},
        )
    except (BotoCoreError, ClientError) as exc:
        raise RuntimeError(f"R2 upload failed: {exc}") from exc

    return f"{config.public_base_url}/{object_key}"
