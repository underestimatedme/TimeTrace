"""Tool adapters: one interface, one implementation per tool."""
from typing import Any, Dict

from keji.adapters.base import ToolAdapter
from keji.adapters.claude import ClaudeAdapter
from keji.adapters.codex import CodexAdapter
from keji.models import CLAUDE, CODEX


def build_adapters(cfg: Dict[str, Any]) -> Dict[str, ToolAdapter]:
    return {CLAUDE: ClaudeAdapter(cfg[CLAUDE]), CODEX: CodexAdapter(cfg[CODEX])}
