"""Per-task git worktree isolation with push disabled (spec §8)."""
import subprocess
import hashlib
import os
from pathlib import Path
from typing import List, Tuple

NO_PUSH_URL = "no_push://blocked"


def snapshot(path: str) -> Tuple[str, str]:
    """Bind HEAD, index, tracked changes and untracked content (including ignored
    files). Filenames alone cannot detect edits to an already-dirty file."""
    head = _git("-C", path, "rev-parse", "HEAD")
    digest = hashlib.sha256()
    for args in (("diff", "--binary", "HEAD", "--"), ("diff", "--cached", "--binary", "HEAD", "--")):
        digest.update(subprocess.check_output(["git", "-C", path] + list(args)))
    untracked = subprocess.check_output(["git", "-C", path, "ls-files", "--others", "-z"])
    for name in sorted(untracked.split(b"\0")):
        if not name:
            continue
        file = Path(path) / os.fsdecode(name)
        digest.update(name + b"\0")
        digest.update(str(file.lstat().st_mode).encode() + b"\0")
        if file.is_symlink():
            digest.update(os.fsencode(os.readlink(file)))
        elif file.is_file():
            with file.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            raise ValueError("cannot checkpoint untracked non-file: %s" % file)
        digest.update(b"\0")
    return head, digest.hexdigest()


def same_repository(path: str, registered: str) -> bool:
    """A saved execution path must still belong to the registered repository."""
    def common(p):
        value = _git("-C", p, "rev-parse", "--git-common-dir")
        return (Path(p) / value).resolve()
    return common(path) == common(registered)


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


def ensure(repo: str, task_id: int, home: Path, base: str = "HEAD") -> Tuple[str, str]:
    """Create (once) the worktree for task_id and return (path, branch).

    `base` is the ref the task branch starts from: HEAD of the repo by default, or the
    branch of the task this one depends on, so follow-up work builds on the previous step.
    """
    path = Path(home) / "worktrees" / str(task_id)
    branch = branch_name(task_id)
    if not (path / ".git").exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        if _branch_exists(repo, branch):
            _git("-C", repo, "worktree", "add", str(path), branch)
        else:
            if base != "HEAD" and not _branch_exists(repo, base):
                raise ValueError("registered base branch no longer exists: %s" % base)
            _git("-C", repo, "worktree", "add", "-b", branch, str(path), base)
    elif _git("-C", str(path), "rev-parse", "--abbrev-ref", "HEAD") != branch:
        raise ValueError("remote worktree is on an unexpected branch: %s" % path)
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
