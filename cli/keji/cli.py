"""argparse front-end. Every subcommand is a thin wrapper over the modules."""
import argparse
from datetime import datetime
import fcntl
import hashlib
import json
import os
import platform
import plistlib
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import quote

from keji import __version__, config, limits, qr, quota, render, scheduler, worktree
from keji.agent import Agent
from keji.cloud import CloudClient
from keji.credentials import CredentialStore, SessionManager
from keji.db import Database
from keji.dispatch import adapter_capabilities, lock_diagnostics
from keji.models import (BLOCKED, CODEX, EV_SAMPLE_FAILURE, FAILED, RUNNABLE, RUNNING, TOOLS,
                         Sample)


def _open(args: argparse.Namespace):
    home = config.home()
    config.ensure_dirs(home)
    cfg = config.load(home)
    db = Database(home / "keji.db")
    return home, cfg, db


def _adapters(cfg: Dict[str, Any]):
    from keji.adapters import build_adapters  # imported lazily: only run/status need tools
    return build_adapters(cfg)


def _log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def _cloud(cfg: Dict[str, Any]) -> CloudClient:
    return CloudClient(str(cfg["cloud_base_url"]))


def _acquire_execution_lock(home: Path):
    lock_file = open(home / "agent.lock", "a+")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_file.close()
        return None
    return lock_file


def _pair_link(user_code: str, name: str) -> str:
    """The keji://pair link shown as a QR code. Only the short user code and a
    display name — never the device code or any token. The name is dropped
    when it would not fit a version-6 QR code."""
    base = "keji://pair?code=%s" % quote(user_code, safe="")
    tail = "&platform=darwin&v=1"
    with_name = "%s&name=%s%s" % (base, quote(name, safe=""), tail)
    try:
        qr.encode(with_name)
        return with_name
    except ValueError:
        return base + tail


def _print_pair_qr(link: str, out=print) -> None:
    lines = qr.render_half_blocks(qr.encode(link))
    colour = out is print and sys.stdout.isatty()
    for line in lines:
        # White on black whatever the terminal theme, so the phone sees dark
        # modules on a light background.
        out("\x1b[97;40m%s\x1b[0m" % line if colour else line)


def pair_computer(cfg: Dict[str, Any], db: Database, home: Path, out=print) -> int:
    """Device-code pairing with the phone (QR code or typed code). Stores the
    runner credentials in the Keychain and reports inventory and quota."""
    cloud = _cloud(cfg)
    name = platform.node() or "Mac"
    auth = cloud.create_device_authorization(name, "darwin", __version__)
    out("用刻迹 iPhone App 的「你的 AI → 扫码绑定」扫描下方二维码（或用相机扫描）：")
    out()
    _print_pair_qr(_pair_link(auth["user_code"], name), out)
    out()
    out("扫不了码时，在「你的 AI → 绑定电脑」中输入：%s" % auth["user_code"])
    out("授权码 %d 分钟内有效，正在等待确认…" % max(1, int(auth["expires_in"]) // 60))
    deadline = time.time() + int(auth["expires_in"])
    while time.time() < deadline:
        approval = cloud.poll_device_authorization(auth["device_code"])
        if approval.get("status") == "approved":
            credentials = cloud.activate(auth["device_code"], approval["activation_code"])
            credentials["expires_at"] = int(time.time()) + int(credentials.get("expires_in") or 900)
            CredentialStore().save(credentials)
            out("已绑定：%s" % credentials["runner"]["name"])
            # Report right away so the phone shows tools and quota within
            # seconds of approving, instead of after the next agent start.
            try:
                adapters = _adapters(cfg)
                token = credentials["access_token"]
                cloud.update_inventory(token, _runner_workspaces(db), _runner_tools(cfg, adapters))
                Agent(db, cloud, adapters, home, lambda: token).report_quota()
                out("已上报工具清单与额度，手机上几秒内可见")
            except Exception as exc:
                out("绑定成功，但首次上报失败：%s（Runner 启动后会重试）" % exc.__class__.__name__)
            return 0
        if approval.get("status") == "expired":
            break
        time.sleep(max(1, int(auth.get("interval") or 5)))
    if out is print:
        print("配对已过期，请重新运行命令", file=sys.stderr)
    else:
        out("配对已过期，请重新运行命令")
    return 1


def cmd_cloud_login(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    return pair_computer(cfg, db, home)


def cmd_cloud_status(args: argparse.Namespace) -> int:
    credentials = CredentialStore().load()
    if not credentials:
        print("未绑定；运行 `keji cloud login`")
        return 1
    runner = credentials.get("runner") or {}
    print("已绑定 %s (%s)" % (runner.get("name", "Mac"), runner.get("id", "unknown")))
    return 0


def cmd_cloud_logout(args: argparse.Namespace) -> int:
    _, cfg, _ = _open(args)
    store = CredentialStore()
    if store.load():
        cloud = _cloud(cfg)
        try:
            cloud.request("POST", "/runner/revoke", None, SessionManager(store, cloud).token())
            print("已在刻迹账号中解绑这台电脑")
        except Exception as exc:
            print("服务端解绑失败（%s），请在手机「设备与授权」里再解绑一次" % exc.__class__.__name__)
    store.delete()
    print("本机 Runner 凭据已从 Keychain 删除")
    return 0


def _workspace_id(path: str) -> str:
    return hashlib.sha256(path.encode("utf-8")).hexdigest()[:24]


def add_workspace(db: Database, path: str, workspace_id: Optional[str] = None,
                  name: Optional[str] = None) -> Dict[str, str]:
    """Register a git repository for remote tasks. Raises ValueError otherwise."""
    path = str(Path(path).expanduser().resolve())
    if not worktree.is_git_repo(path):
        raise ValueError("workspace must be a git repository: %s" % path)
    branch = subprocess.run(["git", "branch", "--show-current"], cwd=path, check=True,
                            capture_output=True, text=True).stdout.strip() or "HEAD"
    workspace_id = workspace_id or _workspace_id(path)
    db.upsert_workspace(workspace_id, name or Path(path).name, path, branch)
    return {"id": workspace_id, "path": path, "default_branch": branch}


def cmd_workspace_add(args: argparse.Namespace) -> int:
    _, _, db = _open(args)
    try:
        added = add_workspace(db, args.path, args.id, args.name)
    except ValueError:
        print("error: workspace must be a git repository", file=sys.stderr)
        return 2
    print("workspace %s added: %s" % (added["id"], added["path"]))
    return 0


def cmd_workspace_list(args: argparse.Namespace) -> int:
    _, _, db = _open(args)
    rows = db.list_workspaces()
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    elif not rows:
        print("no workspaces")
    else:
        for row in rows:
            print("%s  %s  %s" % (row["id"], row["name"], row["path"]))
    return 0


def cmd_workspace_remove(args: argparse.Namespace) -> int:
    _, _, db = _open(args)
    db.remove_workspace(args.id)
    print("workspace %s removed" % args.id)
    return 0


def _runner_workspaces(db: Database) -> list:
    return [{"id": row["id"], "name": row["name"], "default_branch": row["default_branch"]}
            for row in db.list_workspaces()]


def _runner_tools(cfg: Dict[str, Any], adapters: Dict[str, Any]) -> list:
    """Inventory entry per adapter. `plan_tier` is display only; the zero-spend
    flag is the adapter's verified capability, never inferred from a binary."""
    tools = []
    for name, adapter in adapters.items():
        binary = str(cfg.get(name, {}).get("bin", name))
        tier = adapter.plan_tier() if hasattr(adapter, "plan_tier") else None
        tools.append({
            "id": name + "-default", "provider": name, "version": "local",
            "can_enforce_zero_spend": adapter_capabilities(adapter).get("can_enforce_zero_spend") is True,
            "status": "available" if shutil.which(binary) else "unavailable",
            "plan_tier": tier or "",
        })
    return tools


def cmd_agent_run(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    lock_file = _acquire_execution_lock(home)
    if lock_file is None:
        print("error: another keji agent is already running", file=sys.stderr)
        return 1
    cloud = _cloud(cfg)
    state = {"sessions": SessionManager(CredentialStore(), cloud)}
    adapters = _adapters(cfg)

    def token() -> str:
        # Reload after an unbind so a later `keji cloud login` is picked up
        # without restarting the LaunchAgent.
        if getattr(state["sessions"], "credentials", "loaded") is None:
            state["sessions"] = SessionManager(CredentialStore(), cloud)
        return state["sessions"].token()

    def revoked() -> None:
        CredentialStore().delete()
        state["sessions"].credentials = None

    agent = Agent(db, cloud, adapters, home, token,
                  inventory=lambda: (_runner_workspaces(db), _runner_tools(cfg, adapters)),
                  log=_log, on_revoked=revoked,
                  upload_output_tail=bool(cfg.get("upload_output_tail", True)))
    # Startup upkeep pushes the inventory once and reports quota right away.
    agent.maintain(force=True)
    if args.once:
        print(agent.run_once())
        return 0
    agent.run_forever(args.interval)
    return 0


def _iso_local(epoch) -> str:
    try:
        return datetime.fromtimestamp(float(epoch)).strftime("%Y-%m-%d %H:%M:%S")
    except (TypeError, ValueError):
        return "未知时间"


def cmd_agent_doctor(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    paired = CredentialStore().load() is not None
    print("Valley: %s" % cfg["cloud_base_url"])
    print("配对: %s" % ("已完成" if paired else "未完成"))
    print("工作区: %d" % len(db.list_workspaces()))
    adapters = _adapters(cfg)
    for name in TOOLS:
        lines, _ = _tool_check(name, cfg, adapters)
        for line in lines:
            print(line)
        if name in adapters:
            _print_tool_quota(adapters[name])
    diagnostics = lock_diagnostics(home)
    for message in diagnostics:
        print("Execution lock: %s" % message)
    return 0 if paired and db.list_workspaces() and not diagnostics else 1


def _tool_check(name: str, cfg: Dict[str, Any], adapters: Dict[str, Any]):
    """Binary location and zero-spend verdict of one tool: (lines, verified)."""
    binary = str(cfg.get(name, {}).get("bin", name))
    lines = ["%s: %s" % (name, shutil.which(binary) or "未找到")]
    try:
        details = adapters[name].capability_details() if name in adapters else {}
    except Exception as exc:
        details = {"unsupported_reason": "check_failed:" + exc.__class__.__name__}
    verified = details.get("can_enforce_zero_spend") is True
    if verified:
        lines.append("  零付费核验: 通过（%s，%s）" % (details.get("auth_method"), _iso_local(details.get("verified_at"))))
    else:
        lines.append("  零付费核验: 未通过（%s）→ 该工具不会被派发任务" % (details.get("unsupported_reason") or "unknown"))
    return lines, verified


def _print_tool_quota(adapter) -> None:
    """Plan tier and a live quota read, exactly what the phone will show."""
    tier = adapter.plan_tier() if hasattr(adapter, "plan_tier") else None
    print("  套餐: %s" % (tier or "未知"))
    caps = adapter.capabilities() if hasattr(adapter, "capabilities") else {}
    if not caps.get("can_read_quota"):
        print("  额度: 该工具没有主动读取通道")
        return
    try:
        samples = adapter.read_limits() or []
    except Exception as exc:
        print("  额度: 读取失败（%s）" % exc.__class__.__name__)
        return
    if not samples:
        print("  额度: 没有读到窗口")
    for s in samples:
        slot = s.bucket_key.rsplit(":", 1)[-1]
        label = {"short": "短时", "five_hour": "短时", "weekly": "本周", "seven_day": "本周", "monthly": "本月"}.get(
            quota.semantic_scope(slot, s.window_mins), slot)
        reset = ("，%s 重置" % _iso_local(s.reset_at)) if s.reset_at else ""
        print("  额度: %s 剩余 %d%%%s" % (label, round(100 - s.used_pct), reset))


_LAUNCHER = Path(__file__).resolve().parents[1] / "bin" / "keji"


def keji_command() -> List[str]:
    """How to start keji again from launchd or a hook: the checkout's
    launcher when running from a clone, else this interpreter's module
    (pip/pipx installs)."""
    if _LAUNCHER.is_file() and os.access(str(_LAUNCHER), os.X_OK):
        return [str(_LAUNCHER)]
    return [sys.executable, "-m", "keji"]


def install_launch_agent(user_home: Optional[Path] = None, run=subprocess.run) -> Path:
    """Write ~/Library/LaunchAgents/com.keji.run.plist and (re)load it.
    Generated with plistlib, so any path is escaped correctly."""
    user_home = Path(user_home or Path.home())
    destination = user_home / "Library" / "LaunchAgents" / "com.keji.run.plist"
    data_dir = user_home / ".keji"
    doc = {
        "Label": "com.keji.run",
        "ProgramArguments": keji_command() + ["agent", "run"],
        "EnvironmentVariables": {
            # claude's native installer uses ~/.local/bin; Homebrew one of the others.
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:%s" % (user_home / ".local" / "bin"),
            "KEJI_HOME": str(data_dir),
        },
        "RunAtLoad": True,
        "KeepAlive": True,
        "StandardOutPath": str(data_dir / "daemon.log"),
        "StandardErrorPath": str(data_dir / "daemon.err"),
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(doc))
    run(["launchctl", "unload", str(destination)], check=False, capture_output=True)
    run(["launchctl", "load", str(destination)], check=True)
    return destination


def cmd_agent_install(args: argparse.Namespace) -> int:
    destination = install_launch_agent()
    print("Runner 已安装并启动：%s" % destination)
    return 0


def run_setup(args: argparse.Namespace, input_fn=input, print_fn=print) -> int:
    """`keji setup`: tools → repositories → pairing → LaunchAgent.

    Every step reuses the command it stands for (doctor's tool check,
    `workspace add`, `cloud login`, `agent install`). Flags answer the
    questions for scripted installs; end of input means "skip"."""
    out = print_fn

    def ask(question: str) -> Optional[str]:
        try:
            return input_fn(question).strip()
        except EOFError:
            return None

    def confirm(question: str, flag_off: bool) -> bool:
        if flag_off:
            return False
        if args.yes:
            return True
        answer = ask(question + " [Y/n] ")
        return answer is not None and answer.lower() in ("", "y", "yes", "是", "好")

    home, cfg, db = _open(args)
    result = 0
    out("刻迹 Runner 设置（%s）" % home)
    out()
    out("1/4 检查本机 AI 工具")
    adapters = _adapters(cfg)
    verified = []
    for name in TOOLS:
        lines, ok = _tool_check(name, cfg, adapters)
        for line in lines:
            out(line)
        if ok:
            verified.append(name)
    if not verified:
        out("  注意：没有工具通过零付费核验，Runner 不会派发任务。请先用订阅账号登录 claude / codex（不要用 API key）。")
    out()

    out("2/4 选择允许远程任务使用的 Git 仓库")
    for row in db.list_workspaces():
        out("  已登记：%s  %s" % (row["name"], row["path"]))
    pending = list(args.repo or [])
    interactive = not pending and not args.yes
    while True:
        if pending:
            path = pending.pop(0)
        elif interactive:
            path = ask("  仓库路径（回车结束）：")
        else:
            break
        if not path:
            break
        try:
            added = add_workspace(db, path)
            out("  已添加：%s" % added["path"])
        except ValueError:
            out("  不是 git 仓库：%s" % path)
            if not interactive:
                result = 2
    out()

    out("3/4 与手机绑定")
    try:
        existing = CredentialStore().load()
    except Exception:
        existing = None
    if existing:
        out("  已绑定：%s" % ((existing.get("runner") or {}).get("name") or "Mac"))
        # Re-pairing asks with a "no" default and is never implied by --yes.
        do_pair = False
        if not args.no_pair and not args.yes:
            answer = ask("  重新绑定这台电脑？ [y/N] ")
            do_pair = bool(answer) and answer.lower() in ("y", "yes", "是")
    else:
        do_pair = confirm("  现在用手机扫码绑定？", args.no_pair)
    if do_pair:
        try:
            code = pair_computer(cfg, db, home, out=out)
        except Exception as exc:
            out("  绑定失败：%s" % exc.__class__.__name__)
            code = 1
        if code != 0:
            out("  没有完成绑定；之后可以运行 `keji cloud login` 再试。")
            result = result or 1
    out()

    out("4/4 后台 Runner（macOS LaunchAgent，开机自动运行）")
    if confirm("  安装并启动后台 Runner？", args.no_agent):
        try:
            destination = install_launch_agent()
            out("  已安装：%s" % destination)
        except Exception as exc:
            out("  安装失败：%s；可稍后运行 `keji agent install`" % exc.__class__.__name__)
            result = result or 1
    else:
        out("  跳过；需要时运行 `keji agent install`，或前台运行 `keji agent run`。")
    out()
    out("完成。随时运行 `keji agent doctor` 检查状态。" if result == 0 else "部分步骤未完成，见上方提示。")
    return result


def cmd_setup(args: argparse.Namespace) -> int:
    return run_setup(args)


def cmd_config(args: argparse.Namespace) -> int:
    home = config.home()
    try:
        if args.config_cmd == "list":
            cfg = config.load(home)
            for key in sorted(config.scalar_keys()):
                print("%s = %s" % (key, config.format_value(cfg.get(key))))
            return 0
        if args.config_cmd == "get":
            if args.key not in config.scalar_keys():
                config.parse_value(args.key, "")  # raises with the list of keys
            print(config.format_value(config.load(home).get(args.key)))
            return 0
        value = config.set_value(home, args.key, args.value)
    except ValueError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    print("%s = %s  (%s)" % (args.key, config.format_value(value), home / "config.json"))
    if args.key in ("cloud_base_url", "upload_output_tail", "interval_sec"):
        print("restart the Runner to apply: launchctl kickstart -k gui/%d/com.keji.run" % os.getuid())
    return 0


# ---- commands -----------------------------------------------------------------
def cmd_status(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    now = int(time.time())
    adapters = _adapters(cfg)
    try:
        live = adapters[CODEX].read_limits()
        if live:
            limits.record_samples(db, live, now)
    except Exception as exc:
        db.add_event(EV_SAMPLE_FAILURE, tool=CODEX, payload={"error": str(exc)}, at=now)
        print("warning: live Codex quota read failed: %s" % exc, file=sys.stderr)
    rows = limits.snapshot(db)
    binding = limits.binding(rows)
    if args.json:
        print(json.dumps({"now": now, "buckets": rows, "binding": binding}, ensure_ascii=False,
                         indent=2))
    else:
        print(render.status_table(rows, binding, now))
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    repo = os.path.abspath(os.path.expanduser(args.repo))
    if not os.path.isdir(repo) or not worktree.is_git_repo(repo):
        print("error: --repo must be an existing git repository: %s" % repo, file=sys.stderr)
        return 2
    allowed = [os.path.abspath(os.path.expanduser(p)) for p in cfg.get("allowed_repos") or []]
    if allowed and not any(repo == a or repo.startswith(a.rstrip("/") + "/") for a in allowed):
        print("error: %s is outside allowed_repos (%s)" % (repo, ", ".join(allowed)), file=sys.stderr)
        return 2
    if args.after is not None and db.get_task(args.after) is None:
        print("error: --after %d: no such task" % args.after, file=sys.stderr)
        return 2
    prompt = args.prompt if args.prompt != "-" else sys.stdin.read()
    if not prompt.strip():
        print("error: empty prompt", file=sys.stderr)
        return 2
    tid = db.add_task(prompt.strip(), repo, tool=args.tool, any_tool=args.any_tool,
                      depends_on=args.after, on_success=args.on_success, priority=args.priority)
    print("task %d added (%s)" % (tid, "pending" if args.after is not None else "runnable"))
    return 0


def cmd_ls(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    tasks = db.list_tasks(include_done=args.all)
    if args.json:
        print(json.dumps(tasks, ensure_ascii=False, indent=2))
    else:
        print(render.tasks_table(tasks, int(time.time())))
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    lock_file = _acquire_execution_lock(home)
    if lock_file is None:
        print("error: another keji agent is already running", file=sys.stderr)
        return 1
    adapters = _adapters(cfg)
    interval = args.interval or int(cfg.get("interval_sec", 30))
    _log("keji %s daemon, home=%s, interval=%ss%s" % (
        __version__, home, interval, ", once" if args.once else ""))
    _recover_running(db)
    while True:
        try:
            out = scheduler.run_once(db, adapters, cfg, home, log=_log)
        except KeyboardInterrupt:
            raise
        except Exception as exc:  # keep the daemon alive; the event log has the details
            out = "loop error: %s" % exc
            db.add_event("loop_error", payload={"error": str(exc)})
        if out != "idle":
            _log(out)
        if args.once:
            return 0
        try:
            time.sleep(interval if out in ("idle", "circuit open") or out.startswith("loop error")
                       else 1)
        except KeyboardInterrupt:
            _log("stopped")
            return 0


def _recover_running(db: Database) -> None:
    """A task left in `running` means the previous daemon died mid-run. Make it runnable so
    the next loop resumes it with its recorded session id."""
    for t in db.tasks_in_state(RUNNING):
        db.update_task(t["id"], state=RUNNABLE, last_error="daemon restarted mid-run")
        _log("task %d was running when the daemon stopped; will resume" % t["id"])


def cmd_logs(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    run = db.latest_run(args.task_id)
    if not run or not run.get("log_path"):
        print("no runs for task %d" % args.task_id, file=sys.stderr)
        return 1
    path = run["log_path"]
    if not os.path.exists(path):
        print("log file missing: %s" % path, file=sys.stderr)
        return 1
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        sys.stdout.write(fh.read())
        sys.stdout.flush()
        if not args.follow:
            return 0
        try:
            while True:
                chunk = fh.read()
                if chunk:
                    sys.stdout.write(chunk)
                    sys.stdout.flush()
                else:
                    time.sleep(1)
        except KeyboardInterrupt:
            return 0


def cmd_retry(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    t = db.get_task(args.task_id)
    if not t:
        print("no such task", file=sys.stderr)
        return 1
    if t["state"] not in (FAILED, BLOCKED):
        print("task %d is %s; only failed/blocked tasks can be retried" % (t["id"], t["state"]),
              file=sys.stderr)
        return 1
    fields = {"state": RUNNABLE, "blocked_until": None}
    if args.fresh:
        fields["session_id"] = None
    db.update_task(t["id"], **fields)
    print("task %d → runnable%s" % (t["id"], " (fresh session)" if args.fresh else ""))
    return 0


def cmd_rm(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    t = db.get_task(args.task_id)
    if not t:
        print("no such task", file=sys.stderr)
        return 1
    if t["state"] == RUNNING:
        print("task %d is running; stop the daemon first" % t["id"], file=sys.stderr)
        return 1
    db.delete_task(t["id"])
    print("task %d removed (worktree %s left in place)" % (t["id"], t.get("worktree") or "-"))
    return 0


def cmd_events(args: argparse.Namespace) -> int:
    home, cfg, db = _open(args)
    ev = db.list_events(limit=args.limit, type_=args.type)
    if args.json:
        print(json.dumps(ev, ensure_ascii=False, indent=2))
    else:
        print(render.events_table(ev))
    return 0


def cmd_statusline(args: argparse.Namespace) -> int:
    """Claude Code statusLine hook: ingest the interactive session's rate_limits.

    Claude Code pipes a JSON document on stdin every time the status line refreshes.
    When it contains `rate_limits`, we store one sample per window with source
    `statusline`, so quota burned in your own Claude Code sessions (not only keji's
    headless runs) shows up in `keji status` and in the scheduler's exhaustion check.
    Prints a one-line quota summary for the status bar.
    """
    if args.install:
        return _install_statusline()
    raw = sys.stdin.read()
    try:
        doc = json.loads(raw) if raw.strip() else {}
    except ValueError:
        doc = {}
    home, cfg, db = _open(args)
    now = int(time.time())
    rl = doc.get("rate_limits") or {}
    samples = []
    for key, w in rl.items():
        if not isinstance(w, dict) or w.get("used_percentage") is None:
            continue
        samples.append(Sample(
            bucket_key="claude:%s" % key, tool="claude", used_pct=float(w["used_percentage"]),
            reset_at=int(w["resets_at"]) if w.get("resets_at") else None,
            window_mins=300 if key.startswith("five_hour") else (10080 if key.startswith("seven_day") else None),
            is_representative=(key == "five_hour"), source="statusline",
        ))
    if samples:
        limits.record_samples(db, samples, now)
    rows = limits.snapshot(db)
    parts = []
    for r in rows:
        if r["tool"] == "claude" and r["bucket_key"] in ("claude:five_hour", "claude:seven_day"):
            parts.append("%s %d%%" % ("5h" if "five" in r["bucket_key"] else "7d",
                                      round(r["remaining_pct"])))
    codex_rows = [r for r in rows if r["bucket_key"] == "codex:codex:primary"]
    if codex_rows:
        parts.append("codex %d%%" % round(codex_rows[0]["remaining_pct"]))
    b = limits.binding(rows)
    if b:
        parts.append("⏳ %s" % render.countdown(b.get("reset_at"), now))
    print("keji · " + " · ".join(parts) if parts else "keji · no quota data yet")
    return 0


def _install_statusline() -> int:
    """Register `keji statusline` as the statusLine command in ~/.claude/settings.json."""
    settings = Path(os.path.expanduser("~/.claude/settings.json"))
    data: Dict[str, Any] = {}
    if settings.exists():
        try:
            data = json.loads(settings.read_text(encoding="utf-8") or "{}")
        except ValueError:
            print("error: %s is not valid JSON; fix it first" % settings, file=sys.stderr)
            return 1
    keji_bin = " ".join(shlex.quote(part) for part in keji_command())
    current = data.get("statusLine")
    if current and "keji" not in json.dumps(current):
        print("existing statusLine kept, not overwriting: %s" % json.dumps(current), file=sys.stderr)
        print("add `%s statusline` to that script yourself, e.g. pipe stdin through it" % keji_bin,
              file=sys.stderr)
        return 1
    data["statusLine"] = {"type": "command", "command": "%s statusline" % keji_bin}
    settings.parent.mkdir(parents=True, exist_ok=True)
    settings.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("statusLine set in %s → %s statusline" % (settings, keji_bin))
    print("restart Claude Code; quota samples from your interactive sessions now flow into keji")
    return 0


# ---- parser ---------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="keji", description="刻迹 — quota-aware task queue for Claude Code and Codex")
    p.add_argument("--version", action="version", version="keji " + __version__)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("status", help="quota buckets, reset countdowns, binding constraint")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_status)

    a = sub.add_parser("add", help="queue a task")
    a.add_argument("prompt", help="task prompt ('-' reads stdin)")
    a.add_argument("--repo", required=True, help="git repository the task works in")
    a.add_argument("--tool", choices=TOOLS, default=None, help="force a tool (default: auto)")
    a.add_argument("--any-tool", action="store_true", dest="any_tool",
                   help="allow switching tool before start if the chosen one is exhausted")
    a.add_argument("--after", type=int, default=None, help="run only after this task is done")
    a.add_argument("--priority", type=int, default=0)
    a.add_argument("--on-success", dest="on_success", default=None,
                   help="prompt asking the finished session for follow-up tasks (v0.3)")
    a.set_defaults(fn=cmd_add)

    l = sub.add_parser("ls", help="list tasks")
    l.add_argument("--all", action="store_true", help="include done tasks")
    l.add_argument("--json", action="store_true")
    l.set_defaults(fn=cmd_ls)

    r = sub.add_parser("run", help="daemon loop")
    r.add_argument("--once", action="store_true", help="run a single loop iteration and exit")
    r.add_argument("--interval", type=int, default=None, help="seconds between idle polls")
    r.set_defaults(fn=cmd_run)

    g = sub.add_parser("logs", help="show the latest run log of a task")
    g.add_argument("task_id", type=int)
    g.add_argument("-f", "--follow", action="store_true")
    g.set_defaults(fn=cmd_logs)

    t = sub.add_parser("retry", help="put a failed/blocked task back in the queue")
    t.add_argument("task_id", type=int)
    t.add_argument("--fresh", action="store_true", help="drop the session and start over")
    t.set_defaults(fn=cmd_retry)

    d = sub.add_parser("rm", help="delete a task")
    d.add_argument("task_id", type=int)
    d.set_defaults(fn=cmd_rm)

    e = sub.add_parser("events", help="recent events")
    e.add_argument("--limit", type=int, default=50)
    e.add_argument("--type", default=None)
    e.add_argument("--json", action="store_true")
    e.set_defaults(fn=cmd_events)

    sl = sub.add_parser("statusline", help="Claude Code statusLine hook: ingest interactive quota")
    sl.add_argument("--install", action="store_true",
                    help="register this command in ~/.claude/settings.json")
    sl.set_defaults(fn=cmd_statusline)

    cloud = sub.add_parser("cloud", help="bind this Mac to a KeJi account")
    cloud_sub = cloud.add_subparsers(dest="cloud_cmd", required=True)
    cloud_sub.add_parser("login", help="pair this computer").set_defaults(fn=cmd_cloud_login)
    cloud_sub.add_parser("status", help="show pairing status").set_defaults(fn=cmd_cloud_status)
    cloud_sub.add_parser("logout", help="remove local runner credentials").set_defaults(fn=cmd_cloud_logout)

    workspace = sub.add_parser("workspace", help="manage repositories exposed to remote tasks")
    workspace_sub = workspace.add_subparsers(dest="workspace_cmd", required=True)
    wa = workspace_sub.add_parser("add")
    wa.add_argument("path")
    wa.add_argument("--id")
    wa.add_argument("--name")
    wa.set_defaults(fn=cmd_workspace_add)
    wl = workspace_sub.add_parser("list")
    wl.add_argument("--json", action="store_true")
    wl.set_defaults(fn=cmd_workspace_list)
    wr = workspace_sub.add_parser("remove")
    wr.add_argument("id")
    wr.set_defaults(fn=cmd_workspace_remove)

    st = sub.add_parser("setup", help="guided setup: tools, repositories, pairing, LaunchAgent")
    st.add_argument("--repo", action="append", help="register this git repository (repeatable)")
    st.add_argument("--yes", "-y", action="store_true", help="accept the defaults without asking")
    st.add_argument("--no-pair", dest="no_pair", action="store_true", help="skip pairing with the phone")
    st.add_argument("--no-agent", dest="no_agent", action="store_true", help="skip installing the LaunchAgent")
    st.set_defaults(fn=cmd_setup)

    conf = sub.add_parser("config", help="read or change ~/.keji/config.json")
    conf_sub = conf.add_subparsers(dest="config_cmd", required=True)
    conf_sub.add_parser("list", help="show every settable key").set_defaults(fn=cmd_config)
    cg = conf_sub.add_parser("get", help="print a key's effective value")
    cg.add_argument("key")
    cg.set_defaults(fn=cmd_config)
    cs = conf_sub.add_parser("set", help="write a top-level scalar key")
    cs.add_argument("key")
    cs.add_argument("value")
    cs.set_defaults(fn=cmd_config)

    agent = sub.add_parser("agent", help="run the Valley-connected local executor")
    agent_sub = agent.add_subparsers(dest="agent_cmd", required=True)
    ar = agent_sub.add_parser("run")
    ar.add_argument("--once", action="store_true")
    ar.add_argument("--interval", type=int, default=5)
    ar.set_defaults(fn=cmd_agent_run)
    agent_sub.add_parser("doctor", help="check pairing, tools and workspaces").set_defaults(fn=cmd_agent_doctor)
    agent_sub.add_parser("install", help="install the macOS LaunchAgent").set_defaults(fn=cmd_agent_install)
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.fn(args) or 0)
