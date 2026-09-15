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
from keji.checkpoints import Checkpoint, checkpoint_problem
from keji.dispatch import (DispatchGate, LockBusy, adapter_capabilities, adapter_zero_spend_verified,
                           coding_slot_lock, deny_reason, workspace_lock)


def _default_pool_binding(provider: str):
    """Display-only grouping. It does not identify an authenticated account."""
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
        if job.get("status") == "cancelled" or job.get("desired_action") == "cancel":
            self.db.save_remote_claim(claim)
            return self._blocked(claim, job.get("plan_id") or job_id, "cancelled", seq=2 if existing else 1)
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
        provider = job.get("provider")
        adapter = self.adapters.get(provider)
        if adapter is None:
            self._report(claim, [{"seq": 1, "type": "failed", "message": "tool unavailable"}])
            self.db.update_remote_claim(job_id, "reported")
            return "job %s → rejected (tool unavailable)" % job_id
        self.home.joinpath("logs").mkdir(parents=True, exist_ok=True)
        log_file = str(self.home / "logs" / ("remote-%s.log" % job_id))

        plan_key = job.get("plan_id") or job_id
        try:
            checkpoint = self.db.get_checkpoint(plan_key)
        except (TypeError, ValueError, KeyError):
            return self._blocked(claim, plan_key, "checkpoint unreadable; manual recovery required")
        deadline = self._deadline(claim)
        reason = self._gate(adapter, job, deadline)
        if reason:
            return self._blocked(claim, plan_key, reason, checkpoint)
        if checkpoint:
            reason = checkpoint_problem(checkpoint, provider, job["tool_profile_id"],
                                        workspace["path"], adapter_capabilities(adapter).get("can_resume") is True)
            if reason:
                return self._blocked(claim, plan_key, reason, checkpoint)
        elif self.db.plan_started(plan_key) or (existing and existing["state"] != "claimed"):
            return self._blocked(claim, plan_key, "checkpoint missing for previously started job; manual recovery required")

        # Hold both locks through preparation, execution and durable checkpoint/
        # terminal event persistence. A crashed owner leaves a persistent fence.
        try:
            slot = coding_slot_lock(self.home).acquire()
        except LockBusy:
            return "job %s → deferred (runner busy)" % job_id
        try:
            ws_lock = workspace_lock(self.home, workspace["path"]).acquire()
        except LockBusy:
            slot.release()
            return "job %s → deferred (workspace busy)" % job_id
        try:
            return self._execute(claim, workspace, adapter, checkpoint, plan_key, log_file, deadline)
        finally:
            ws_lock.release()
            slot.release()

    @staticmethod
    def _deadline(lease):
        try:
            return datetime.fromisoformat(lease["lease_expires_at"].replace("Z", "+00:00")).timestamp()
        except (KeyError, TypeError, ValueError, AttributeError):
            return 0.0

    def _gate(self, adapter, job, deadline):
        reason = deny_reason(DispatchGate(
            cancelled=job.get("status") == "cancelled" or job.get("desired_action") == "cancel",
            lease_valid=deadline > time.time(), runner_online=True, dependencies_ready=True,
            zero_spend_verified=self._zero_spend(adapter, job),
        ))
        if reason:
            return reason
        if adapter_capabilities(adapter).get("can_dispatch") is not True:
            return "dispatch_unavailable"
        return ""

    def _renew(self, claim, adapter, deadline):
        # Once a lease expires the old owner cannot regain execution authority.
        reason = self._gate(adapter, claim["job"], deadline)
        if reason:
            return deadline, reason
        done = threading.Event()
        answer = []
        def request():
            try:
                answer.append(self.cloud.renew(self.access_token(), claim["attempt_id"], claim["lease_epoch"]))
            except Exception:
                pass
            finally:
                done.set()
        # A blocked HTTP/credential call must not hold the writer past expiry.
        # The abandoned daemon can finish its request but cannot grant a lease
        # or mutate the claim after this wait has failed.
        threading.Thread(target=request, daemon=True).start()
        if not done.wait(max(0, deadline - time.time())):
            return deadline, "lease_expired"
        lease = answer[0] if answer else None
        if not isinstance(lease, dict):
            return deadline, "lease renewal failed"
        if lease.get("desired_action") == "cancel":
            claim["job"]["desired_action"] = "cancel"
        renewed = self._deadline(lease)
        # Include time spent in the renewal request: a late response cannot
        # bridge an interval in which this owner no longer held a lease.
        if time.time() >= deadline and claim["job"].get("desired_action") != "cancel":
            return deadline, "lease_expired"
        return renewed, self._gate(adapter, claim["job"], renewed)

    def _blocked(self, claim, plan_key, reason, checkpoint=None, seq=1):
        cancelled = reason == "cancelled"
        if cancelled:
            self.db.delete_checkpoint(plan_key)
        elif checkpoint:
            checkpoint.reason = reason
            self.db.save_checkpoint(checkpoint)
        event_type = "cancelled" if cancelled else "waiting_input"
        self._report(claim, [{"seq": seq, "type": event_type, "message": "dispatch blocked: %s" % reason}])
        self.db.update_remote_claim(claim["job"]["id"], "reported")
        if cancelled:
            return "job %s → cancelled" % claim["job"]["id"]
        if reason.startswith("checkpoint"):
            return "job %s → waiting_input (%s)" % (claim["job"]["id"], reason)
        return "job %s → blocked (%s)" % (claim["job"]["id"], reason)

    def _execute(self, claim, workspace, adapter, checkpoint, plan_key, log_file, deadline):
        job = claim["job"]
        job_id = job["id"]
        resuming = checkpoint is not None
        session_id = checkpoint.provider_session_id if resuming else str(uuid.uuid4())
        # Reuse the original execution worktree even if recovery has a new job id.
        execution_job = checkpoint.job_id if resuming else job_id
        local_id = int(hashlib.sha256(execution_job.encode("utf-8")).hexdigest()[:12], 16)
        reason = self._gate(adapter, job, deadline)
        if reason:
            return self._blocked(claim, plan_key, reason, checkpoint)
        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                preparation = pool.submit(self.prepare_workspace, workspace["path"], local_id,
                                          self.home, workspace["default_branch"])
                reason = ""
                while True:
                    try:
                        wait = self.heartbeat_interval if reason else min(self.heartbeat_interval, max(.001, (deadline - time.time()) / 2))
                        execution_path, _ = preparation.result(timeout=wait)
                        break
                    except TimeoutError:
                        if not reason:
                            deadline, reason = self._renew(claim, adapter, deadline)
                        # Preparation may still be using git. Keep locks until it
                        # stops; a failed renewal never authorises a later spawn.
                if reason:
                    return self._blocked(claim, plan_key, reason, checkpoint)
                execution_path = str(Path(execution_path).resolve())
                if resuming:
                    reason = checkpoint_problem(checkpoint, job["provider"], job["tool_profile_id"],
                                                workspace["path"], adapter_capabilities(adapter).get("can_resume") is True)
                    if not reason and checkpoint.execution_path != execution_path:
                        reason = "checkpoint execution directory changed"
                    if not reason and not worktree.same_repository(execution_path, workspace["path"]):
                        reason = "checkpoint repository changed"
                    if not reason and worktree.snapshot(execution_path) != (checkpoint.git_head, checkpoint.dirty_paths_digest):
                        reason = "checkpoint git state changed"
                    if reason:
                        return self._blocked(claim, plan_key, reason, checkpoint)

                # Check authority again after potentially slow git operations.
                reason = self._gate(adapter, job, deadline)
                if not reason and resuming and adapter_capabilities(adapter).get("can_resume") is not True:
                    reason = "checkpoint resume capability changed"
                if reason:
                    return self._blocked(claim, plan_key, reason, checkpoint)
                self.db.update_remote_claim(job_id, "launching")
                self._report(claim, [{"seq": 1, "type": "running", "message": "started"}])
                self.db.update_remote_claim(job_id, "running")
                # Reporting can block on the network; check authority again at
                # the actual call boundary, not only before announcing the run.
                deadline, reason = self._renew(claim, adapter, deadline)
                if not reason and resuming and adapter_capabilities(adapter).get("can_resume") is not True:
                    reason = "checkpoint resume capability changed"
                if reason:
                    return self._blocked(claim, plan_key, reason, checkpoint, seq=2)
                self.db.mark_plan_started(plan_key, job_id, claim["attempt_id"])
                Path(log_file).touch(exist_ok=True)
                cancel_event = threading.Event()
                run = adapter.resume if resuming else adapter.start
                spawned = False
                def invoke():
                    nonlocal reason, spawned
                    # Executor scheduling is also a delay: fence inside the
                    # worker, at the call that can actually create a process.
                    if reason or cancel_event.is_set():
                        return None
                    reason = self._gate(adapter, job, deadline)
                    if not reason and resuming and adapter_capabilities(adapter).get("can_resume") is not True:
                        reason = "checkpoint resume capability changed"
                    if reason:
                        return None
                    spawned = True
                    return run(job["prompt"], execution_path, session_id, log_file, cancel_event)
                future = pool.submit(invoke)
                while True:
                    try:
                        wait = self.heartbeat_interval if reason else min(self.heartbeat_interval, max(.001, (deadline - time.time()) / 2))
                        result = future.result(timeout=wait)
                        break
                    except TimeoutError:
                        if not reason:
                            deadline, reason = self._renew(claim, adapter, deadline)
                            if reason:
                                cancel_event.set()
                reason = reason or self._gate(adapter, job, deadline)
                if reason:
                    if not spawned or reason == "cancelled":
                        return self._blocked(claim, plan_key, reason, checkpoint, seq=2)
                    self.db.delete_checkpoint(plan_key)
                    self.db.update_remote_claim(job_id, "fenced")
                    return "job %s → fenced (%s)" % (job_id, reason)
        except Exception as exc:
            # Invalid recovery evidence must survive for manual diagnosis.
            if resuming:
                return self._blocked(claim, plan_key, "checkpoint recovery failed: %s" % exc, checkpoint)
            self._report(claim, [{"seq": 2, "type": "failed", "message": "adapter/preparation crashed: %s" % exc}])
            self.db.update_remote_claim(job_id, "reported")
            return "job %s → failed" % job_id

        if result.ok:
            self.db.delete_checkpoint(plan_key)
            event = {"seq": 2, "type": "completed", "message": "completed",
                     "result_summary": (result.output or "completed")[:1000]}
            outcome = "awaiting_review"
        elif result.blocked:
            if result.samples:
                self._post_samples(job["provider"], adapter, result.samples)
            try:
                head, dirty_digest = worktree.snapshot(execution_path)
                cp = Checkpoint(
                    plan_id=plan_key, job_id=execution_job, attempt_id=claim["attempt_id"],
                    tool_profile_id=job["tool_profile_id"], provider=job["provider"],
                    # Only an adapter-confirmed native session is resumable.
                    provider_session_id=result.session_id or "",
                    canonical_workspace=workspace["path"], execution_path=execution_path,
                    git_head=head, dirty_paths_digest=dirty_digest, output_path=str(Path(log_file).resolve()),
                    last_output_offset=Path(log_file).stat().st_size, completed_criteria=[],
                    side_effect_summary=(result.output or "")[:200], reason="waiting_quota",
                )
                self.db.save_checkpoint(cp)
            except Exception as exc:
                return self._blocked(claim, plan_key, "checkpoint capture failed: %s" % exc, checkpoint, seq=2)
            outcome = "waiting_quota"
            event = {"seq": 2, "type": outcome, "message": (result.error or "quota blocked")[:1000]}
        else:
            self.db.delete_checkpoint(plan_key)
            outcome = "failed"
            event = {"seq": 2, "type": outcome, "message": (result.error or "exit %s" % result.exit_code)[:1000]}
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
        binding = self._pool_binding(provider)
        pool_id, profile_id = binding[:2]
        # Two-field legacy/display bindings remain non-authoritative. Only an
        # explicitly verified third flag can identify the authenticated pool.
        authoritative = len(binding) == 3 and binding[2] is True
        payloads = []
        for s in samples:
            try:
                payloads.append(quota.payload_from_reading(
                    s.bucket_key, s.tool, s.used_pct, s.reset_at, s.window_mins,
                    pool_id, profile_id, now, source=getattr(s, "source", "runner"),
                    pool_authoritative=authoritative,
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
