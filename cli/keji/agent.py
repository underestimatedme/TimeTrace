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
from keji import quota, worktree
from keji.checkpoints import Checkpoint, resume_allowed
from keji.dispatch import (DispatchGate, LockBusy, adapter_zero_spend_verified,
                           coding_slot_lock, deny_reason, workspace_lock)


def _default_pool_binding(provider: str):
    """Opaque per-provider account pool + local profile reference. R4 replaces
    this with an explicit user-chosen profile↔pool binding."""
    return "pool-" + provider, provider + "-personal"


def _capability_zero_spend(adapter: Any, job: Dict[str, Any]) -> bool:
    """Safe default: only a verified adapter capability authorises spend-free
    execution. A manual/source claim can never grant it."""
    return adapter_zero_spend_verified(adapter)


class Agent:
    def __init__(self, db: Database, cloud: Any, adapters: Dict[str, Any], home: Path,
                 access_token: Callable[[], str], prepare_workspace: Callable = worktree.ensure,
                 heartbeat_interval: float = 30,
                 zero_spend_verified: Callable[[Any, Dict[str, Any]], bool] = _capability_zero_spend,
                 pool_binding: Callable[[str], Any] = _default_pool_binding):
        self.db, self.cloud, self.adapters = db, cloud, adapters
        self.home, self.access_token = Path(home), access_token
        self.prepare_workspace = prepare_workspace
        self.heartbeat_interval = heartbeat_interval
        self._zero_spend = zero_spend_verified
        self._pool_binding = pool_binding

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

        # Resume the original provider session when a durable checkpoint exists
        # for this Plan and the tool profile is unchanged; otherwise start fresh.
        plan_key = job.get("plan_id") or job_id
        tool_profile_id = job["tool_profile_id"]
        native_resume = bool(getattr(adapter, "capabilities", lambda: {})().get("can_resume", False))
        checkpoint = self.db.get_checkpoint(plan_key)
        resuming = bool(
            checkpoint and checkpoint.provider_session_id
            and resume_allowed(checkpoint.tool_profile_id, tool_profile_id, native_resume)
        )
        session_id = checkpoint.provider_session_id if resuming else str(uuid.uuid4())
        lease_deadline = (datetime.fromisoformat(
            claim["lease_expires_at"].replace("Z", "+00:00")
        ).timestamp() if claim.get("lease_expires_at") else time.time() + 90)

        # One gate for every start/resume: nothing runs while cancelled, past its
        # lease, without ready dependencies, or without a verified zero-additional-
        # spend guarantee.
        gate = DispatchGate(
            cancelled=(job.get("status") == "cancelled" or job.get("desired_action") == "cancel"),
            lease_valid=lease_deadline > time.time(),
            runner_online=True,
            dependencies_ready=True,
            zero_spend_verified=self._zero_spend(adapter, job),
        )
        reason = deny_reason(gate)
        if reason is not None:
            event_type = "cancelled" if reason == "cancelled" else "waiting_input"
            self._report(claim, [{"seq": 1, "type": event_type, "message": "dispatch blocked: %s" % reason}])
            self.db.update_remote_claim(job_id, "reported")
            return "job %s → blocked (%s)" % (job_id, reason)

        # Fence local and remote dispatch through file locks: one coding slot per
        # runner, one writer per canonical workspace. A second process is denied
        # and defers rather than double-running the Plan/working directory.
        try:
            slot = coding_slot_lock(self.home).acquire()
        except LockBusy:
            return "job %s → deferred (runner busy)" % job_id
        try:
            ws_lock = workspace_lock(self.home, workspace["path"]).acquire()
        except LockBusy:
            slot.release()
            return "job %s → deferred (workspace busy)" % job_id

        error = ""
        lease_lost = False
        try:
            self.db.update_remote_claim(job_id, "launching")
            self._report(claim, [{"seq": 1, "type": "running", "message": "started"}])
            self.db.update_remote_claim(job_id, "running")
            local_id = int(hashlib.sha256(job_id.encode("utf-8")).hexdigest()[:12], 16)
            execution_path, _ = self.prepare_workspace(workspace["path"], local_id, self.home, workspace["default_branch"])
            with ThreadPoolExecutor(max_workers=1) as pool:
                cancel_event = threading.Event()
                run = adapter.resume if resuming else adapter.start
                future = pool.submit(run, job["prompt"], execution_path, session_id, log_file, cancel_event)
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
        finally:
            ws_lock.release()
            slot.release()
        if lease_lost:
            self.db.update_remote_claim(job_id, "fenced")
            return "job %s → fenced (lease lost)" % job_id
        if result is not None and result.ok:
            event = {"seq": 2, "type": "completed", "message": "completed",
                     "result_summary": (result.output or "completed")[:1000]}
            outcome = "awaiting_review"
            self.db.delete_checkpoint(plan_key)  # done: no stale resume
        else:
            message = error if result is None else (result.error or "exit %s" % result.exit_code)
            event_type = "cancelled" if error == "cancelled by user" else ("waiting_quota" if result is not None and result.blocked else "failed")
            event = {"seq": 2, "type": event_type, "message": message[:1000]}
            outcome = event_type
            if event_type == "waiting_quota":
                # Report the exhaustion reading so Valley's gate parks siblings
                # and knows when the pool recovers.
                if result is not None and result.samples:
                    self._post_samples(provider, adapter, result.samples)
                # Durable checkpoint so natural quota recovery can resume the same
                # provider session in the same workspace.
                self.db.save_checkpoint(Checkpoint(
                    plan_id=plan_key, job_id=job_id, attempt_id=claim["attempt_id"],
                    tool_profile_id=tool_profile_id,
                    provider_session_id=(result.session_id or session_id),
                    canonical_workspace=workspace["path"], git_head="", dirty_paths_digest="",
                    last_output_offset=0, completed_criteria=[],
                    side_effect_summary=(result.output or "")[:200], reason="waiting_quota",
                ))
            else:
                # cancelled / failed: drop any checkpoint so nothing auto-resumes.
                self.db.delete_checkpoint(plan_key)
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
                    # No work: refresh quota so parked plans recover promptly.
                    try:
                        self.report_quota()
                    except Exception:
                        pass
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

    def _post_samples(self, provider: str, adapter: Any, samples: list, now: float = None) -> int:
        """Map local vendor readings to de-identified Valley samples and post
        them so the server's quota gate reflects real availability."""
        if not samples:
            return 0
        now = now if now is not None else time.time()
        pool_id, profile_id = self._pool_binding(provider)
        payloads = []
        for s in samples:
            try:
                payloads.append(quota.payload_from_reading(
                    s.bucket_key, s.tool, s.used_pct, s.reset_at, s.window_mins,
                    pool_id, profile_id, now, source=getattr(s, "source", "runner"),
                ))
            except ValueError:
                continue
        if not payloads:
            return 0
        try:
            self.cloud.post_quota_samples(self.access_token(), payloads)
        except Exception:
            return 0
        return len(payloads)

    def report_quota(self, now: float = None) -> int:
        """Read on-demand quota from adapters that support it and report it to
        Valley. This is what lets a parked (waiting_quota) Plan be re-queued when
        its pool recovers, without needing a run to discover it."""
        now = now if now is not None else time.time()
        total = 0
        for provider, adapter in self.adapters.items():
            caps = getattr(adapter, "capabilities", lambda: {})()
            if not caps.get("can_read_quota"):
                continue
            try:
                samples = adapter.read_limits()
            except Exception:
                continue
            total += self._post_samples(provider, adapter, samples or [], now)
        return total

    def flush_outbox(self) -> None:
        for row in self.db.pending_remote_events():
            self.cloud.append_events(self.access_token(), row["job_id"], row["attempt_id"],
                                     row["lease_epoch"], [row["payload"]])
            self.db.mark_remote_event_sent(row["id"])
