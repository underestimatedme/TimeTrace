"""One gate for every start/resume, plus the file locks that fence concurrent
dispatch on a single runner.

Both the cloud agent and the local scheduler must funnel through here so a Plan /
workspace is never driven by two processes at once, and nothing runs without a
verifiable zero-additional-spend guarantee.
"""
import errno
import fcntl
import hashlib
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class DispatchGate:
    cancelled: bool
    lease_valid: bool
    runner_online: bool
    dependencies_ready: bool
    zero_spend_verified: bool


def deny_reason(gate: DispatchGate) -> Optional[str]:
    """First blocking reason, or None when dispatch may proceed. Cancellation
    dominates; a missing billing guarantee always blocks."""
    checks = [
        (gate.cancelled, "cancelled"),
        (not gate.lease_valid, "lease_expired"),
        (not gate.runner_online, "runner_offline"),
        (not gate.dependencies_ready, "dependencies_pending"),
        (not gate.zero_spend_verified, "billing_unverified"),
    ]
    return next((reason for blocked, reason in checks if blocked), None)


def adapter_capabilities(adapter: Any) -> Dict[str, bool]:
    """Read an adapter capability declaration without trusting its surface."""
    capabilities = getattr(adapter, "capabilities", None)
    if not callable(capabilities):
        return {}
    try:
        caps = capabilities()
    except Exception:
        return {}
    return caps if isinstance(caps, dict) else {}


def adapter_zero_spend_verified(adapter: Any) -> bool:
    """Return true only when an adapter explicitly verifies zero-spend mode."""
    return adapter_capabilities(adapter).get("can_enforce_zero_spend") is True


class LockBusy(RuntimeError):
    """Raised when a non-blocking file lock is already held elsewhere."""


class FileLock:
    """Non-blocking exclusive advisory lock over a lock file. flock treats each
    open file description independently, so a second acquirer — even in the same
    process — is denied while the first holds it."""

    def __init__(self, path: str):
        self.path = str(path)
        self._fd: Optional[int] = None

    def acquire(self) -> "FileLock":
        Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            os.close(fd)
            if exc.errno in (errno.EACCES, errno.EAGAIN):
                raise LockBusy(self.path) from exc
            raise
        os.write(fd, str(os.getpid()).encode())
        self._fd = fd
        return self

    def release(self) -> None:
        if self._fd is not None:
            try:
                fcntl.flock(self._fd, fcntl.LOCK_UN)
            finally:
                os.close(self._fd)
                self._fd = None

    def __enter__(self) -> "FileLock":
        return self.acquire()

    def __exit__(self, *exc) -> None:
        self.release()


def _locks_dir(home) -> Path:
    return Path(home) / "locks"


def coding_slot_lock(home) -> FileLock:
    """Runner-wide single-coding-process slot. First release ships one process
    per runner (spec constraint)."""
    return FileLock(str(_locks_dir(home) / "coding-slot.lock"))


def workspace_lock(home, canonical_path: str) -> FileLock:
    """Per canonical-workspace lock so the same working directory is never
    written by two concurrent runs."""
    digest = hashlib.sha256(os.path.realpath(canonical_path).encode("utf-8")).hexdigest()[:16]
    return FileLock(str(_locks_dir(home) / ("workspace-%s.lock" % digest)))
