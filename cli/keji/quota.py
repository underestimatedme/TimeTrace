"""Quota semantics for the runner (total-plan §4 contract).

Pure tri-state availability plus safe capability defaults. Unknown quota is
never treated as full, and a manually-sourced claim can never grant the
billing-safety capability that gates unattended execution.
"""
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

# The five capabilities from the total plan. All default False; only an adapter's
# real check or verified local config may raise one.
CAPABILITY_KEYS = (
    "can_record",
    "can_read_quota",
    "can_dispatch",
    "can_resume",
    "can_enforce_zero_spend",
)


@dataclass(frozen=True)
class Window:
    """One applicable quota window. used_percent is None when the reading is
    unknown; observed_at/expires_at/reset_at are epoch seconds."""

    used_percent: Optional[float]
    reset_at: Optional[float]
    observed_at: float
    expires_at: float


def availability(windows: List[Window], now: float) -> str:
    """available / blocked / unknown over a pool's applicable windows.

    Any fresh exhausted window blocks (so a weekly block is not bypassed by a
    fresh short window). A missing, stale, or unknown-reading window makes the
    pool unknown. Only when every applicable window is fresh and under budget is
    the pool available.
    """
    fresh = [w for w in windows if w.observed_at <= now < w.expires_at]
    if any(w.used_percent is not None and w.used_percent >= 100 for w in fresh):
        return "blocked"
    if not windows or len(fresh) != len(windows) or any(w.used_percent is None for w in fresh):
        return "unknown"
    return "available"


def parse_used_percent(value: Any) -> Optional[float]:
    """Reject NaN/inf/negative/>100; None stays None (unknown reading)."""
    if value is None:
        return None
    number = float(value)
    if math.isnan(number) or math.isinf(number) or number < 0 or number > 100:
        raise ValueError("used_percent must be within [0, 100]")
    return number


def make_window(used_percent: Any, reset_at: Optional[float], observed_at: float, expires_at: float) -> Window:
    """Validated Window constructor. A freshness horizon cannot outlive a trusted
    reset boundary, and it must be strictly after the observation time."""
    used = parse_used_percent(used_percent)
    if expires_at <= observed_at:
        raise ValueError("expires_at must be after observed_at")
    if reset_at is not None and expires_at > reset_at:
        expires_at = reset_at
    return Window(used, reset_at, observed_at, expires_at)


def default_capabilities() -> Dict[str, bool]:
    return {key: False for key in CAPABILITY_KEYS}


def merge_capabilities(verified: Optional[Dict[str, Any]]) -> Dict[str, bool]:
    """Overlay verified capability flags onto the all-False baseline, ignoring
    unknown keys so a caller cannot smuggle in extra state."""
    caps = default_capabilities()
    for key, value in (verified or {}).items():
        if key in caps:
            caps[key] = bool(value)
    return caps


def _iso(epoch: Optional[float]) -> Optional[str]:
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def payload_from_reading(bucket_key: str, tool: str, used_percent: Any, reset_at: Optional[float],
                         window_mins: Optional[int], pool_id: str, profile_id: str, now: float,
                         source: str = "runner", confidence: str = "exact",
                         default_ttl: float = 3600.0) -> Dict[str, Any]:
    """Wrap one vendor rate-limit reading as a Valley sample. A reset time is
    only trusted when it is still in the future; otherwise the reading is fresh
    for a bounded horizon and carries no reset boundary."""
    scope = bucket_key.rsplit(":", 1)[-1] if ":" in bucket_key else (bucket_key or "primary")
    trusted_reset = reset_at if (reset_at is not None and reset_at > now) else None
    expires = trusted_reset if trusted_reset is not None else now + (window_mins * 60 if window_mins else default_ttl)
    window = make_window(used_percent, trusted_reset, now, expires)
    return sample_payload(
        sample_id="%s:%s:%d" % (tool, bucket_key, int(now)), pool_id=pool_id, profile_id=profile_id,
        scope=scope, kind=tool, window=window, source=source, confidence=confidence,
    )


def sample_payload(sample_id: str, pool_id: str, profile_id: str, scope: str, kind: str,
                   window: Window, source: str, confidence: str) -> Dict[str, Any]:
    """Wire shape for POST /runner/quota/samples. Carries only opaque ids and
    de-identified readings — never tokens, account emails, or environment."""
    return {
        "sample_id": sample_id,
        "pool_id": pool_id,
        "profile_id": profile_id,
        "scope": scope,
        "kind": kind,
        "used_percent": window.used_percent,
        "reset_at": _iso(window.reset_at),
        "observed_at": _iso(window.observed_at),
        "expires_at": _iso(window.expires_at),
        "source": source,
        "confidence": confidence,
    }
