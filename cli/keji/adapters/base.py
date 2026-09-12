"""ToolAdapter interface plus the subprocess helper both adapters share."""
from typing import List, Optional

from keji.models import RunResult, Sample
from keji.process import run_streaming

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
