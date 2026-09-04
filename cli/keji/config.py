"""Configuration: spec §9 defaults deep-merged with ~/.keji/config.json."""
import copy
import json
import os
from pathlib import Path
from typing import Any, Dict

DEFAULTS: Dict[str, Any] = {
    "interval_sec": 30,
    "jitter_sec": 300,
    "default_block_sleep_sec": 3600,
    "circuit_breaker_failures": 3,
    "circuit_window_mins": 300,
    "allowed_repos": [],
    "hook_max_tasks": 5,
    "claude": {
        "bin": "claude",
        "permission_mode": "acceptEdits",
        # Local git operations the unattended run may perform without asking.
        # Pushing stays blocked by --disallowedTools and the worktree pushurl.
        "allowed_tools": [
            "Bash(git add:*)", "Bash(git commit:*)", "Bash(git status:*)",
            "Bash(git diff:*)", "Bash(git log:*)",
        ],
        "model": None,
        "extra_args": [],
    },
    "codex": {
        "bin": "codex",
        "sandbox": "workspace-write",
        "model": None,
        "extra_args": [],
    },
}


def home() -> Path:
    """Data directory. KEJI_HOME overrides ~/.keji (tests rely on this)."""
    return Path(os.environ.get("KEJI_HOME") or Path.home() / ".keji")


def _merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    out = copy.deepcopy(base)
    for k, v in override.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = v
    return out


def load(home_dir: Path = None) -> Dict[str, Any]:
    home_dir = home_dir or home()
    path = home_dir / "config.json"
    if not path.exists():
        return copy.deepcopy(DEFAULTS)
    with open(path, "r", encoding="utf-8") as fh:
        user = json.load(fh)
    if not isinstance(user, dict):
        raise ValueError("config.json must contain a JSON object")
    return _merge(DEFAULTS, user)


def ensure_dirs(home_dir: Path) -> None:
    for sub in ("", "logs", "inbox", "inbox/done", "inbox/rejected", "worktrees"):
        (home_dir / sub).mkdir(parents=True, exist_ok=True)
