"""Per-task git worktree isolation with push disabled (spec §8)."""
import subprocess
import hashlib
import os
import re
from pathlib import Path
from typing import List, Tuple

NO_PUSH_URL = "no_push://blocked"

# Every git call the runner makes inside a worktree a model has touched runs
# with these overrides: no fsmonitor command, no hooks. Config-driven command
# execution is otherwise closed by verify_metadata().
SAFE_GIT = ("-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null")

_CONFIG_WORKTREE_LINE = re.compile(r'^(?:\[remote "[^"\\\n]*"\]|pushurl = ' + re.escape(NO_PUSH_URL) + r')$')


class MetadataTampered(ValueError):
    """The worktree's git metadata no longer matches what the runner created."""


def snapshot(path: str) -> Tuple[str, str]:
    """Bind HEAD, index, tracked changes and untracked content (including ignored
    files). Filenames alone cannot detect edits to an already-dirty file."""
    head = _git(*SAFE_GIT, "-C", path, "rev-parse", "HEAD")
    digest = hashlib.sha256()
    for args in (("diff", "--binary", "HEAD", "--"), ("diff", "--cached", "--binary", "HEAD", "--")):
        digest.update(subprocess.check_output(["git"] + list(SAFE_GIT) + ["-C", path, args[0], "--no-ext-diff",
                                               "--ignore-submodules=all"] + list(args[1:])))
    # A gitlink belongs to the parent index, not to the child working tree.
    # Bind its commit (and conflict stage) without opening the child directory.
    gitlinks = {}
    index = subprocess.check_output(["git"] + list(SAFE_GIT) + ["-C", path, "ls-files", "--stage", "-z"])
    for entry in index.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, commit, stage = metadata.split()
        if mode == b"160000":
            gitlinks.setdefault(name, []).append(stage + b":" + commit)
    # Read tracked bytes too: git diff deliberately hides assume-unchanged and
    # skip-worktree entries and therefore cannot be our content authority.
    files = subprocess.check_output(["git"] + list(SAFE_GIT) + ["-C", path, "ls-files", "--cached", "--others", "-z"])
    for name in sorted(set(files.split(b"\0"))):
        if not name:
            continue
        digest.update(name + b"\0")
        if name in gitlinks:
            digest.update(b"gitlink\0" + b"\0".join(sorted(gitlinks[name])) + b"\0")
            continue
        file = Path(path) / os.fsdecode(name)
        if not file.exists() and not file.is_symlink():
            digest.update(b"missing\0")
            continue
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


def git_common_dir(path: str) -> str:
    """Absolute path of the repository metadata a checkout writes to. For a
    linked worktree that is the main repo's .git, outside the worktree itself."""
    common = _git("-C", path, "rev-parse", "--git-common-dir")
    return str((Path(path) / common).resolve()) if not os.path.isabs(common) else str(Path(common).resolve())


def _read_small(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise MetadataTampered("%s is not a regular file" % path.name)
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read(64 * 1024)


def verify_metadata(path: str, repo: str) -> None:
    """Refuse to run git in `path` unless its metadata is what `ensure` made.

    A sandboxed run can write the worktree and its per-worktree admin dir.
    Redirecting `.git` / `commondir`, or adding keys such as core.fsmonitor or
    include.path to config.worktree, would make the runner's own unsandboxed
    git calls execute attacker-chosen commands. The registered repository is
    the trusted anchor: its common dir is not writable from the sandbox."""
    root = Path(path)
    common = Path(git_common_dir(repo)).resolve()
    dotgit = root / ".git"
    if dotgit.is_dir() and not dotgit.is_symlink():
        if root.resolve() == Path(repo).resolve():
            return  # the registered main checkout itself
        raise MetadataTampered("not a linked worktree of the registered repository")
    match = re.fullmatch(r"gitdir: (.+?)\n?", _read_small(dotgit))
    if not match:
        raise MetadataTampered(".git file is malformed")
    admin = Path(match.group(1))
    admin = (admin if admin.is_absolute() else root / admin)
    if admin.is_symlink() or admin.resolve().parent != common / "worktrees":
        raise MetadataTampered(".git points outside the registered repository")
    admin = admin.resolve()
    commondir = _read_small(admin / "commondir").strip()
    target = Path(commondir) if os.path.isabs(commondir) else admin / commondir
    if target.resolve() != common:
        raise MetadataTampered("commondir points outside the registered repository")
    config_worktree = admin / "config.worktree"
    if config_worktree.exists() or config_worktree.is_symlink():
        for line in _read_small(config_worktree).splitlines():
            line = line.strip()
            if line and not _CONFIG_WORKTREE_LINE.match(line):
                raise MetadataTampered("config.worktree holds keys the runner did not write")


def sandbox_write_roots(path: str) -> List[str]:
    """Directories outside a linked worktree that `git add`/`git commit` in it
    must write: its own admin dir, the object store, and the directory of its
    branch ref (plus that ref's reflog dir). Never the whole common dir: the
    shared config and hooks there are executed by unsandboxed git later."""
    root = Path(path).resolve()
    common = Path(git_common_dir(path)).resolve()
    if root == common or root in common.parents:
        return []
    admin = Path(_git(*SAFE_GIT, "-C", path, "rev-parse", "--absolute-git-dir")).resolve()
    if admin.parent != common / "worktrees":
        return []
    roots = [admin, common / "objects"]
    branch = _git(*SAFE_GIT, "-C", path, "symbolic-ref", "--quiet", "--short", "HEAD")
    if branch and ".." not in branch.split("/"):
        for base in (common / "refs" / "heads", common / "logs" / "refs" / "heads"):
            ref_dir = (base / branch).parent
            ref_dir.mkdir(parents=True, exist_ok=True)
            roots.append(ref_dir)
    return [str(r) for r in roots]


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
    else:
        verify_metadata(str(path), repo)
        if _git(*SAFE_GIT, "-C", str(path), "rev-parse", "--abbrev-ref", "HEAD") != branch:
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
