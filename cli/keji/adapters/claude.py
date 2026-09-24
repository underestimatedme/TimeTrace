"""Claude Code adapter: `claude -p --output-format stream-json`.

Facts this relies on (verified 2026-09-02 on Claude Code 2.1.258, see
cli/探针验证记录-2026-09-02.md):
- every -p run emits one `rate_limit_event` whose `rate_limit_info.unifiedWindows`
  holds per-window utilization (0..1) and resetsAt; `rateLimitType` names the
  binding window; `status` is allowed / allowed_warning / rejected.
- the final `result` message carries session_id, is_error, subtype, api_error_status.
- there is NO on-demand quota query, so read_limits() returns None.
"""
import json
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from keji.adapters.base import SAFETY_RULES, ToolAdapter, run_streaming
from keji.billing import billing_env_keys, claude_verifier
from keji import tiers
from keji.adapters import claude_usage
from keji.models import CLAUDE, RunResult, Sample
from keji.quota import merge_capabilities

LIMIT_TEXT_MARKERS = ("hit your limit", "usage limit", "rate limit")


def build_cmd(
    cfg: Dict[str, Any], prompt: str, session_id: Optional[str] = None,
    resume: Optional[str] = None,
) -> List[str]:
    cmd = [cfg.get("bin", "claude"), "-p", "--output-format", "stream-json", "--verbose"]
    if resume:
        cmd += ["--resume", resume]
    elif session_id:
        cmd += ["--session-id", session_id]
    cmd += ["--permission-mode", cfg.get("permission_mode", "acceptEdits")]
    cmd += ["--disallowedTools", "Bash(git push*)"]
    allowed = list(cfg.get("allowed_tools") or [])
    if allowed:
        cmd += ["--allowedTools"] + allowed
    if cfg.get("model"):
        cmd += ["--model", cfg["model"]]
    cmd += ["--append-system-prompt", SAFETY_RULES]
    cmd += list(cfg.get("extra_args") or [])
    cmd += [prompt]
    return cmd


def parse_stream(lines: List[str]) -> RunResult:
    """Turn stream-json lines into a RunResult (exit_code left for the caller)."""
    res = RunResult()
    for raw in lines:
        raw = raw.strip()
        if not raw.startswith("{"):
            continue
        try:
            msg = json.loads(raw)
        except ValueError:
            continue
        mtype = msg.get("type")
        if mtype == "rate_limit_event":
            _apply_rate_limit(msg.get("rate_limit_info") or {}, res)
        elif mtype == "result":
            _apply_result(msg, res)
        if not res.session_id and msg.get("session_id"):
            res.session_id = msg["session_id"]
    return res


def _apply_rate_limit(info: Dict[str, Any], res: RunResult) -> None:
    rep = info.get("rateLimitType")
    windows = info.get("unifiedWindows") or {}
    for key, w in windows.items():
        util = w.get("utilization")
        if util is None:
            continue
        res.samples.append(Sample(
            bucket_key="claude:%s" % key, tool=CLAUDE, used_pct=round(float(util) * 100, 2),
            reset_at=_int_or_none(w.get("resetsAt")), window_mins=_window_mins(key),
            is_representative=(key == rep), source="run",
        ))
    if info.get("status") == "rejected":
        res.blocked = True
        res.reset_at = _int_or_none(info.get("resetsAt")) or res.reset_at
    elif info.get("resetsAt") and rep:
        # remember the binding window's reset even when allowed; used if we get blocked later
        res.reset_at = res.reset_at or _int_or_none(info.get("resetsAt"))


def _apply_result(msg: Dict[str, Any], res: RunResult) -> None:
    res.output = msg.get("result") or ""
    res.session_id = msg.get("session_id") or res.session_id
    is_error = bool(msg.get("is_error"))
    status = msg.get("api_error_status")
    text = (res.output or "").lower()
    if status == 429 or any(m in text for m in LIMIT_TEXT_MARKERS) and is_error:
        res.blocked = True
    if is_error and not res.blocked:
        res.error = "%s: %s" % (msg.get("subtype", "error"), res.output[:500])
    res.ok = (not is_error) and (not res.blocked) and msg.get("subtype") == "success"


def _window_mins(key: str) -> Optional[int]:
    if key.startswith("five_hour"):
        return 300
    if key.startswith("seven_day"):
        return 7 * 24 * 60
    return None


def _int_or_none(v: Any) -> Optional[int]:
    try:
        return int(v) if v is not None else None
    except (TypeError, ValueError):
        return None


class ClaudeAdapter(ToolAdapter):
    name = CLAUDE
    adapter_version = "claude-code/0.4"

    def __init__(self, cfg: Dict[str, Any], billing=None, credentials=None):
        self.cfg = cfg
        # The local OAuth login (file, else Keychain). Tests inject a stub so
        # they never touch the developer's real login.
        self._credentials = credentials or (lambda: tiers.claude_oauth(self.credentials_path()))
        # Real check: `claude auth status` must report a claude.ai subscription
        # login with the first-party provider, and no API-key path may exist in
        # the environment or settings. Tests inject a StaticBilling.
        self.billing = billing or claude_verifier(cfg)

    def credentials_path(self) -> Path:
        return Path(self.cfg.get("credentials_path") or Path.home() / ".claude" / ".credentials.json")

    def plan_tier(self) -> Optional[str]:
        return tiers.claude_plan_tier(self.credentials_path())

    def read_limits(self) -> Optional[List[Sample]]:
        """On-demand read through the OAuth usage endpoint; None when the local
        login is missing, expired, or the endpoint refuses."""
        return claude_usage.usage_samples(self._credentials(), now=time.time())

    def capabilities(self) -> Dict[str, bool]:
        # Implemented surface: records runs, reads quota on demand through the
        # OAuth usage endpoint when a local login exists, dispatches headless,
        # resumes the original session via `--resume`. Zero-spend comes only
        # from the billing verdict; unverified keeps the gate closed.
        return merge_capabilities({
            "can_record": True,
            "can_read_quota": bool((self._credentials() or {}).get("accessToken")),
            "can_dispatch": True,
            "can_resume": True,
            "can_enforce_zero_spend": self.billing.verdict().verified,
        })

    def read_limits(self) -> Optional[List[Sample]]:
        return None  # no on-demand channel; samples come from runs

    def start(self, prompt: str, cwd: str, session_id: str, log_file: str, cancel_event=None) -> RunResult:
        return self._run(build_cmd(self.cfg, prompt, session_id=session_id), cwd, log_file,
						 session_id, cancel_event)

    def resume(self, prompt: str, cwd: str, session_id: str, log_file: str, cancel_event=None) -> RunResult:
        return self._run(build_cmd(self.cfg, prompt, resume=session_id), cwd, log_file,
                         session_id, cancel_event)

    def _run(self, cmd: List[str], cwd: str, log_file: str, session_id: str, cancel_event=None) -> RunResult:
        code, lines = run_streaming(cmd, cwd, log_file, timeout=float(self.cfg.get("timeout_seconds", 3600)),
                                    cancel_event=cancel_event, drop_env=billing_env_keys(CLAUDE))
        res = parse_stream(lines)
        res.exit_code = code
        res.session_id = res.session_id or session_id
        if code != 0 and not res.blocked and res.ok:
            res.ok = False
        if code != 0 and not res.blocked and not res.error:
            res.error = "claude exited with %d" % code
        return res
