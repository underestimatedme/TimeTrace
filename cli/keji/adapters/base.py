"""ToolAdapter interface plus the subprocess helper both adapters share."""
import os
import subprocess
from typing import IO, List, Optional, Sequence, Tuple

from keji.models import RunResult, Sample

# Appended to every headless run (spec §8). Both tools get the same text.
SAFETY_RULES = (
    "You are running unattended inside an isolated git worktree created for this task.\n"
    "Hard rules:\n"
    "1. Never run `git push`, never touch remote branches, never modify CI configuration"
    " (.github/workflows, .gitlab-ci.yml, Jenkinsfile, etc.).\n"
    "2. Commit your work to the CURRENT branch only. Do not create, checkout or delete other branches.\n"
    "3. Only read and write files inside the current working directory.\n"
    "4. If the task is impossible or unsafe, stop and explain instead of improvising.\n"
)


class ToolAdapter:
    """Uniform surface over Claude Code and Codex. Subclasses fill the three methods."""

    name = "base"

    def read_limits(self) -> Optional[List[Sample]]:
        """On-demand quota read. Return None when the tool has no such channel."""
        return None

    def start(self, prompt: str, cwd: str, session_id: str, log_file: str) -> RunResult:
        raise NotImplementedError

    def resume(self, prompt: str, cwd: str, session_id: str, log_file: str) -> RunResult:
        raise NotImplementedError


def run_streaming(
    cmd: Sequence[str], cwd: str, log_file: str, env: Optional[dict] = None,
    timeout: Optional[int] = None,
) -> Tuple[int, List[str]]:
    """Run cmd with stdin=/dev/null, tee stdout lines into log_file, return (exit, lines).

    stderr is appended to the same log after stdout so a reader sees the tool's own
    messages next to the structured stream.
    """
    lines: List[str] = []
    run_env = dict(os.environ)
    # Never inherit a parent Claude Code session's identity into the child run.
    for k in list(run_env):
        if k.startswith("CLAUDE"):
            run_env.pop(k, None)
    if env:
        run_env.update(env)
    with open(log_file, "a", encoding="utf-8") as log:
        log.write("$ " + " ".join(_shell_quote(c) for c in cmd) + "\n")
        log.flush()
        with open(os.devnull, "rb") as devnull:
            proc = subprocess.Popen(
                list(cmd), cwd=cwd, stdin=devnull, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, env=run_env, text=True, bufsize=1,
            )
        assert proc.stdout is not None and proc.stderr is not None
        _tee(proc.stdout, log, lines)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        err = proc.stderr.read()
        if err:
            log.write("--- stderr ---\n" + err)
        log.write("--- exit %s ---\n" % proc.returncode)
    return int(proc.returncode), lines


def _tee(stream: IO[str], log: IO[str], lines: List[str]) -> None:
    for line in iter(stream.readline, ""):
        lines.append(line.rstrip("\n"))
        log.write(line)
        log.flush()


def _shell_quote(s: str) -> str:
    if not s or any(ch in s for ch in " \t\n\"'$`\\"):
        return "'" + s.replace("'", "'\\''") + "'"
    return s
