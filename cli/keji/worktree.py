"""Per-task git worktree isolation with push disabled (spec §8)."""
import subprocess
from pathlib import Path
from typing import List, Tuple

NO_PUSH_URL = "no_push://blocked"


def _git(*args: str, cwd: str = None) -> str:
    out = subprocess.run(
        ["git"] + list(args), cwd=cwd, check=True, capture_output=True, text=True
    )
    return out.stdout.strip()


def is_git_repo(path: str) -> bool:
    try:
        return _git("-C", path, "rev-parse", "--is-inside-work-tree") == "true"
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def branch_name(task_id: int) -> str:
    return "keji/%d" % task_id


def ensure(repo: str, task_id: int, home: Path) -> Tuple[str, str]:
    """Create (once) the worktree for task_id and return (path, branch)."""
    path = Path(home) / "worktrees" / str(task_id)
    branch = branch_name(task_id)
    if not (path / ".git").exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        if _branch_exists(repo, branch):
            _git("-C", repo, "worktree", "add", str(path), branch)
        else:
            _git("-C", repo, "worktree", "add", "-b", branch, str(path), "HEAD")
    block_push(str(path))
    return str(path), branch


def _branch_exists(repo: str, branch: str) -> bool:
    try:
        _git("-C", repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch)
        return True
    except subprocess.CalledProcessError:
        return False


def remotes(path: str) -> List[str]:
    out = _git("-C", path, "remote")
    return [r for r in out.splitlines() if r.strip()]


def block_push(path: str) -> None:
    """Point every remote's pushurl at an invalid scheme so `git push` cannot work.

    Written with `--worktree` so only this worktree is affected; the user's main
    checkout keeps its normal push URL. Requires extensions.worktreeConfig, which
    is switched on in the shared config (harmless for the main checkout).
    """
    rs = remotes(path)
    if not rs:
        return
    _git("-C", path, "config", "extensions.worktreeConfig", "true")
    for r in rs:
        _git("-C", path, "config", "--worktree", "remote.%s.pushurl" % r, NO_PUSH_URL)
