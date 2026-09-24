"""On-demand Claude Code quota via the OAuth usage endpoint that Claude Code's
own /usage command calls. The access token comes from the local credentials
(file, else the macOS Keychain item Claude Code uses), is sent once, and is
never stored, logged, or returned."""
import json
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from keji import tiers
from keji.models import CLAUDE, Sample

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
WINDOWS = (("five_hour", 300), ("seven_day", 7 * 24 * 60))


def _epoch(value: Any) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def _percent(value: Any) -> Optional[float]:
    """Utilization as reported: the endpoint speaks percent (41.0 = 41 %,
    observed live on 2026-09-25). No fraction heuristic — it would turn a
    0.5 % reading into 50 % and an exhausted 1.0 into 1 %."""
    try:
        return round(float(value), 2)
    except (TypeError, ValueError):
        return None


def read_usage(credentials_path: Path, opener: Optional[Callable] = None,
               now: Optional[float] = None,
               keychain: Callable[[], Optional[str]] = tiers.keychain_secret) -> Optional[List[Sample]]:
    return usage_samples(tiers.claude_oauth(credentials_path, keychain), opener=opener, now=now)


def usage_samples(oauth: Dict[str, Any], opener: Optional[Callable] = None,
                  now: Optional[float] = None) -> Optional[List[Sample]]:
    """Samples for an already-loaded `claudeAiOauth` object (see tiers.claude_oauth).
    `opener` is resolved at call time so tests can patch urllib."""
    opener = opener or urllib.request.urlopen
    token = str((oauth or {}).get("accessToken") or "")
    if not token:
        return None
    expires_ms = oauth.get("expiresAt")
    if expires_ms is not None and now is not None:
        try:
            if float(expires_ms) / 1000 <= now:
                return None  # let Claude Code refresh it; never send a stale token
        except (TypeError, ValueError):
            pass
    request = urllib.request.Request(USAGE_URL)
    request.add_header("Authorization", "Bearer " + token)
    request.add_header("anthropic-beta", "oauth-2025-04-20")
    request.add_header("Accept", "application/json")
    request.add_header("User-Agent", "keji-runner")
    try:
        with opener(request, timeout=15) as response:
            doc = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError, AttributeError):
        return None
    samples: List[Sample] = []
    for key, mins in WINDOWS:
        window = doc.get(key) if isinstance(doc, dict) else None
        if not isinstance(window, dict):
            continue
        used = _percent(window.get("utilization"))
        if used is None:
            continue
        samples.append(Sample(bucket_key="claude:" + key, tool=CLAUDE, used_pct=used,
                              reset_at=_epoch(window.get("resets_at")), window_mins=mins,
                              is_representative=(key == "five_hour"), source="live"))
    return samples or None
