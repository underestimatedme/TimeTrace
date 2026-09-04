"""argparse front-end. Every subcommand is a thin wrapper over the modules."""
import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from keji import __version__, config, limits, render, scheduler, worktree
from keji.db import Database
from keji.models import (BLOCKED, CODEX, EV_SAMPLE_FAILURE, FAILED, RUNNABLE, RUNNING, TOOLS)


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
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.fn(args) or 0)
