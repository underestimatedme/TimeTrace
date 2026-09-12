"""Outbound-only Valley runner loop."""
import time
import uuid
import hashlib
import threading
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from pathlib import Path
from typing import Any, Callable, Dict

from keji.db import Database
from keji import worktree


class Agent:
    def __init__(self, db: Database, cloud: Any, adapters: Dict[str, Any], home: Path,
                 access_token: Callable[[], str], prepare_workspace: Callable = worktree.ensure,
                 heartbeat_interval: float = 30):
        self.db, self.cloud, self.adapters = db, cloud, adapters
        self.home, self.access_token = Path(home), access_token
        self.prepare_workspace = prepare_workspace
        self.heartbeat_interval = heartbeat_interval

    def run_once(self) -> str:
        self.flush_outbox()
        token = self.access_token()
        claim = self.cloud.claim(token)
        if not claim:
            return "idle"
        job = claim["job"]
        job_id = job["id"]
        existing = self.db.get_remote_claim(job_id)
        if (existing and existing["attempt_id"] == claim["attempt_id"]
                and existing["state"] in ("launching", "running", "reported")):
            return "job %s → duplicate ignored" % job_id
        self.db.save_remote_claim(claim)  # durable before any local process starts
        workspace = self.db.get_workspace(job["workspace_id"])
        registered = Path(workspace["path"]) if workspace else None
        if (not registered or not registered.is_dir()
                or str(registered.resolve()) != workspace["path"]
                or not worktree.is_git_repo(workspace["path"])):
            self._report(claim, [{"seq": 1, "type": "failed", "message": "unknown workspace"}])
            self.db.update_remote_claim(job_id, "reported")
            return "job %s → rejected (unknown workspace)" % job_id
        provider = job["tool_profile_id"].split("-", 1)[0]
        adapter = self.adapters.get(provider)
        if adapter is None:
            self._report(claim, [{"seq": 1, "type": "failed", "message": "tool unavailable"}])
            self.db.update_remote_claim(job_id, "reported")
            return "job %s → rejected (tool unavailable)" % job_id
        self.home.joinpath("logs").mkdir(parents=True, exist_ok=True)
        log_file = str(self.home / "logs" / ("remote-%s.log" % job_id))
        session_id = str(uuid.uuid4())
        self.db.update_remote_claim(job_id, "launching")
        self._report(claim, [{"seq": 1, "type": "running", "message": "started"}])
        self.db.update_remote_claim(job_id, "running")
        error = ""
        lease_lost = False
        lease_deadline = (datetime.fromisoformat(
            claim["lease_expires_at"].replace("Z", "+00:00")
        ).timestamp() if claim.get("lease_expires_at") else time.time() + 90)
        try:
            local_id = int(hashlib.sha256(job_id.encode("utf-8")).hexdigest()[:12], 16)
            execution_path, _ = self.prepare_workspace(workspace["path"], local_id, self.home, workspace["default_branch"])
            with ThreadPoolExecutor(max_workers=1) as pool:
                cancel_event = threading.Event()
                future = pool.submit(adapter.start, job["prompt"], execution_path, session_id, log_file, cancel_event)
                while True:
                    try:
                        result = future.result(timeout=self.heartbeat_interval)
                        break
                    except TimeoutError:
                        try:
                            lease = self.cloud.renew(self.access_token(), claim["attempt_id"], claim["lease_epoch"])
                        except Exception:
                            lease = {}
                            if time.time() >= lease_deadline - 2:
                                lease_lost = True
                                cancel_event.set()
                        if lease.get("lease_expires_at"):
                            lease_deadline = datetime.fromisoformat(
                                lease["lease_expires_at"].replace("Z", "+00:00")
                            ).timestamp()
                        if lease.get("desired_action") == "cancel":
                            cancel_event.set()
            if cancel_event.is_set():
                result = None
                error = "lease lost" if lease_lost else "cancelled by user"
        except Exception as exc:
            result = None
            error = "adapter crashed: %s" % exc
        if lease_lost:
            self.db.update_remote_claim(job_id, "fenced")
            return "job %s → fenced (lease lost)" % job_id
        if result is not None and result.ok:
            event = {"seq": 2, "type": "completed", "message": "completed",
                     "result_summary": (result.output or "completed")[:1000]}
            outcome = "awaiting_review"
        else:
            message = error if result is None else (result.error or "exit %s" % result.exit_code)
            event_type = "cancelled" if error == "cancelled by user" else ("waiting_quota" if result is not None and result.blocked else "failed")
            event = {"seq": 2, "type": event_type, "message": message[:1000]}
            outcome = event_type
        self._report(claim, [event])
        self.db.update_remote_claim(job_id, "reported")
        return "job %s → %s" % (job_id, outcome)

    def run_forever(self, interval: int = 5) -> None:
        backoff = interval
        while True:
            try:
                outcome = self.run_once()
                backoff = interval
                if outcome == "idle":
                    time.sleep(interval)
            except Exception:
                time.sleep(backoff)
                backoff = min(60, max(interval, backoff * 2))

    def _report(self, claim: Dict[str, Any], events: list) -> None:
        for event in events:
            self.db.queue_remote_event(claim["job"]["id"], claim["attempt_id"], claim["lease_epoch"], event)
        try:
            self.flush_outbox()
        except Exception:
            pass

    def flush_outbox(self) -> None:
        for row in self.db.pending_remote_events():
            self.cloud.append_events(self.access_token(), row["job_id"], row["attempt_id"],
                                     row["lease_epoch"], [row["payload"]])
            self.db.mark_remote_event_sent(row["id"])
