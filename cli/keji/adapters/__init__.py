"""Tool adapters: one interface, one implementation per tool."""
from typing import Any, Dict

from keji.adapters.base import ToolAdapter
from keji.adapters.claude import ClaudeAdapter
from keji.adapters.codex import CodexAdapter
from keji.adapters.cursor import CursorAdapter
from keji.adapters.gemini import GeminiAdapter
from keji.models import CLAUDE, CODEX


def build_adapters(cfg: Dict[str, Any]) -> Dict[str, ToolAdapter]:
    adapters: Dict[str, ToolAdapter] = {CLAUDE: ClaudeAdapter(cfg[CLAUDE]), CODEX: CodexAdapter(cfg[CODEX])}
    # Management-tier tools register only when the user has configured a profile;
    # they can record but never dispatch/resume.
    if cfg.get("cursor"):
        adapters["cursor"] = CursorAdapter(cfg["cursor"])
    if cfg.get("gemini"):
        adapters["gemini"] = GeminiAdapter(cfg["gemini"])
    return adapters
