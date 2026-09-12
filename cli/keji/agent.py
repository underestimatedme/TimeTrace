"""Outbound-only Valley runner loop."""
import time
import uuid
import hashlib
from pathlib import Path
from typing import Any, Callable, Dict

from keji.db import Database
from keji import worktree


class Agent:
    def __init__(self, db: Database, cloud: Any, adapters: Dict[str, Any], home: Path,
                 access_token: Callable[[], str], prepare_workspace: Callable = worktree.ensure):
        self.db, self.cloud, self.adapters = db, cloud, adapters
        self.home, self.access_token = Path(home), access_token
        self.prepare_workspace = prepare_workspace

    def run_once(self) -> str:
        self.flush_outbox()
        token = self.access_token()
        claim = self.cloud.claim(token)
        if not claim:
            return "idle"
        job = claim["job"]
        job_id = job["id"]
        self.db.save_remote_claim(claim)  # durable before any local process starts
        workspace = self.db.get_workspace(job["workspace_id"])
        if not workspace or not Path(workspace["path"]).is_dir():
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
        self.db.update_remote_claim(job_id, "running")
        self._report(claim, [{"seq": 1, "type": "running", "message": "started"}])
        try:
            local_id = int(hashlib.sha256(job_id.encode("utf-8")).hexdigest()[:12], 16)
            execution_path, _ = self.prepare_workspace(workspace["path"], local_id, self.home)
            result = adapter.start(job["prompt"], execution_path, session_id, log_file)
        except Exception as exc:
            result = None
            error = "adapter crashed: %s" % exc
        if result is not None and result.ok:
            event = {"seq": 2, "type": "completed", "message": "completed",
                     "result_summary": (result.output or "completed")[:1000]}
            outcome = "awaiting_review"
        else:
            message = error if result is None else (result.error or "exit %s" % result.exit_code)
            event_type = "waiting_quota" if result is not None and result.blocked else "failed"
            event = {"seq": 2, "type": event_type, "message": message[:1000]}
            outcome = event_type
        self._report(claim, [event])
        self.db.update_remote_claim(job_id, "reported")
        return "job %s → %s" % (job_id, outcome)

    def run_forever(self, interval: int = 5) -> None:
        while True:
            outcome = self.run_once()
            if outcome == "idle":
                time.sleep(interval)

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
