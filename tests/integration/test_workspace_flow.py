"""Real Valley router/PostgreSQL + Agent/CloudClient/SQLite contract suite.

Run via Valley's permanent TestWorkspacePythonIntegration; configuration arrives
on stdin. Only the external AI adapter is simulated. Faults interrupt the real
HTTP transport before delivery or after the real response has been received.
"""
import json
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "cli"))
from keji.agent import Agent
from keji.cloud import CloudClient, CloudError
from keji.db import Database
from keji.models import RunResult

CONFIG = {}


def stamp(value=None):
    return (value or datetime.now(timezone.utc)).isoformat().replace("+00:00", "Z")


class FaultTransport:
    """A transport fault around urlopen, never a fabricated server response."""
    mode = None
    occurred = False

    def __call__(self, request, **kwargs):
        events = request.full_url.endswith("/events")
        if events and self.mode == "offline":
            self.occurred = True
            raise OSError("integration transport disconnected")
        response = urllib.request.urlopen(request, **kwargs)
        if events and self.mode == "lost_reply":
            response.read()
            response.close()
            self.occurred = True
            self.mode = "offline"
            raise OSError("integration response lost after commit")
        return response


class ExternalAI:
    """The sole service fake: deterministic native-session adapter contract."""
    def __init__(self, action="complete", cancel=None):
        self.action, self.cancel = action, cancel
        self.native_session = "fake-native-" + uuid.uuid4().hex
        self.resumed = []

    def capabilities(self):
        return {"can_dispatch": True, "can_resume": True, "can_enforce_zero_spend": True}

    def start(self, prompt, cwd, session_id, log_file, cancel_event):
        if self.action == "cancel":
            self.cancel()
            if not cancel_event.wait(5):
                raise AssertionError("runner missed HTTP cancellation")
            return RunResult(exit_code=143, error="cancelled")
        if self.action == "pause":
            return RunResult(blocked=True, session_id=self.native_session, error="quota exhausted")
        return RunResult(ok=True, output="reviewable integration result")

    def resume(self, prompt, cwd, session_id, log_file, cancel_event):
        if session_id != self.native_session:
            raise AssertionError("runner did not resume original provider session")
        self.resumed.append(session_id)
        return RunResult(ok=True, session_id=session_id, output="resumed integration result")


class WorkspaceFlowTests(unittest.TestCase):
    def setUp(self):
        if not CONFIG.get("url", "").startswith("http://127.0.0.1:"):
            self.fail("run through Valley TestWorkspacePythonIntegration with isolated PostgreSQL")
        self.transport = FaultTransport()
        self.cloud = CloudClient(CONFIG["url"], opener=self.transport)
        identity = "f12-" + uuid.uuid4().hex + "@example.invalid"
        self.cloud.request("POST", "/auth/send-code", {"identifier": identity})
        self.owner = self.cloud.request("POST", "/auth/login", {"identifier": identity, "code": "246810"})["access_token"]
        self.temp = tempfile.TemporaryDirectory(prefix="f12-runner-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.repo, check=True)
        subprocess.run(["git", "-c", "user.name=Integration", "-c", "user.email=integration@example.invalid",
                        "commit", "--allow-empty", "-qm", "initial"], cwd=self.repo, check=True)
        self.db = Database(self.home / "runner.sqlite")
        self.addCleanup(lambda: self.db.close())
        self.db.upsert_workspace("workspace", "fixture", str(self.repo.resolve()), "main")
        self.runner = self.pair("runner-one")
        self.inventory(self.runner)
        self.sample(self.runner, "primary", 10)

    def api(self, method, path, body=None):
        return self.cloud.request(method, path, body, self.owner)

    def pair(self, name):
        device = self.cloud.create_device_authorization(name, "darwin", "f12-integration")
        self.api("POST", "/device-authorizations/approve", {"user_code": device["user_code"]})
        approval = self.cloud.poll_device_authorization(device["device_code"])
        return self.cloud.activate(device["device_code"], approval["activation_code"])

    def inventory(self, runner, billing=True):
        tool = {"id": "codex-default", "provider": "codex", "version": "fake-integration-only", "status": "available"}
        if billing is not None:
            tool["can_enforce_zero_spend"] = billing
        self.cloud.update_inventory(runner["access_token"], [{"id": "workspace", "name": "Integration", "default_branch": "main"}], [tool])

    def sample(self, runner, scope, used):
        now = datetime.now(timezone.utc)
        self.cloud.post_quota_samples(runner["access_token"], [{
            "sample_id": uuid.uuid4().hex, "pool_id": "f12-pool", "profile_id": "codex-default",
            "kind": "codex", "limit_id": "codex:codex", "scope": scope,
            "window_mins": 10080 if scope == "weekly" else 300, "pool_authoritative": True,
            "used_percent": used, "observed_at": stamp(now), "expires_at": stamp(now + timedelta(hours=1)),
            "reset_at": stamp(now + timedelta(hours=2)), "source": "runner", "confidence": "exact"}])

    def create(self, runner=None, commitment=False, not_before=None):
        runner = runner or self.runner
        task_id = uuid.uuid4().hex
        now = stamp()
        self.api("POST", "/sync", {"upserts": {
            "projects": [{"id": "project", "name": "Integration", "status": "active", "created_at": now, "updated_at": now}],
            "tasks": [{"id": task_id, "project_id": "project", "title": "Integration task", "description": "",
                       "executor_type": "ai", "ai_provider": "codex", "status": "todo", "priority": "medium",
                       "estimated_minutes": 5, "created_at": now, "updated_at": now}]}})
        plan = self.api("POST", "/tasks/" + task_id + "/plans", {
            "title": "Integration plan", "criteria": ["review result"], "work_weight": 1,
            "status": "ready", "depends_on": [],
            "execution_policy": {"max_additional_spend_minor": 0, "allow_auto_resume": True}})
        if commitment:
            self.api("POST", "/tasks/" + task_id + "/report-commitments", {
                "date": datetime.now(timezone.utc).date().isoformat(), "zone": "UTC",
                "expected_baseline_revision": 0, "task_weight": 1, "purpose": "user_work",
                "plan_revisions": {plan["id"]: plan["revision"]}})
        task = next(t for t in self.api("GET", "/bootstrap")["state"]["tasks"] if t["id"] == task_id)
        revision = int(datetime.strptime(task["updated_at"].replace("Z", "+00:00"), "%Y-%m-%dT%H:%M:%S.%f%z").timestamp() * 1000)
        body = {
            "task_id": task_id, "plan_id": plan["id"], "runner_id": runner["runner"]["id"],
            "workspace_id": "workspace", "tool_profile_id": "codex-default", "prompt": "integration instruction",
            "idempotency_key": uuid.uuid4().hex, "expected_task_revision": revision}
        if not_before:
            body["not_before"] = not_before
        job = self.api("POST", "/remote-jobs", body)
        return plan, job

    def agent(self, adapter):
        return Agent(self.db, self.cloud, {"codex": adapter}, self.home,
                     lambda: self.runner["access_token"], heartbeat_interval=.02)

    def job(self, job):
        return self.api("GET", "/remote-jobs/" + job["id"])

    def plan(self, plan):
        return next(p for p in self.api("GET", "/tasks/" + plan["task_id"] + "/plans") if p["id"] == plan["id"])

    def evidence(self, job, session=None):
        rows = self.db.conn.execute("SELECT id,attempt_id,payload FROM remote_outbox WHERE job_id=? ORDER BY id", (job["id"],)).fetchall()
        claim = self.db.get_remote_claim(job["id"])
        events = []
        for row in rows:
            payload = json.loads(row[2])
            events.append({"attempt_id": row[1], "seq": payload["seq"], "type": payload["type"], "observed_at": payload["observed_at"]})
        print("EVIDENCE " + json.dumps({"test": self._testMethodName, "job_id": job["id"],
                          "attempt_id": claim["attempt_id"], "lease_epoch": claim["lease_epoch"],
                          "sqlite_event_ids": [r[0] for r in rows], "events": events, "provider_session_id": session}), flush=True)

    def test_full_flow_quota_checkpoint_native_resume_accept_report(self):
        plan, job = self.create(commitment=True)
        adapter = ExternalAI("pause")
        self.assertIn("waiting_quota", self.agent(adapter).run_once())
        cp = self.db.get_checkpoint(plan["id"])
        self.assertEqual(cp.provider_session_id, adapter.native_session)
        first_claim = self.db.get_remote_claim(job["id"])
        self.evidence(job, cp.provider_session_id)
        self.sample(self.runner, "weekly", 100)
        quota = self.api("GET", "/quota")
        self.assertTrue(any(p["availability"] == "blocked" for p in quota["pools"]))
        self.assertEqual("idle", self.agent(adapter).run_once())
        self.sample(self.runner, "primary", 0)
        self.assertEqual("idle", self.agent(adapter).run_once(), "short window must not bypass exhausted week")
        self.sample(self.runner, "weekly", 5)
        self.assertIn("awaiting_review", self.agent(adapter).run_once())
        self.assertEqual(adapter.resumed, [adapter.native_session])
        second_claim = self.db.get_remote_claim(job["id"])
        self.assertNotEqual(first_claim["attempt_id"], second_claim["attempt_id"])
        self.assertGreater(second_claim["lease_epoch"], first_claim["lease_epoch"])
        self.assertIsNone(self.db.get_checkpoint(plan["id"]))
        self.assertEqual(self.job(job)["status"], "awaiting_review")
        current = self.plan(plan)
        with self.assertRaises(CloudError) as missing:
            self.api("POST", "/plans/" + plan["id"] + "/accept", {
                "expected_revision": current["revision"], "criteria": [], "evidence_ids": [job["id"]]})
        self.assertEqual(missing.exception.status, 422)
        accepted = self.api("POST", "/plans/" + plan["id"] + "/accept", {
            "expected_revision": current["revision"], "criteria": [{"index": 0, "accepted": True}],
            "evidence_ids": [job["id"]], "rework_count": 0})
        self.assertEqual(accepted["status"], "accepted")
        self.assertEqual(self.job(job)["status"], "completed")
        report = self.api("POST", "/reports", {"date": datetime.now(timezone.utc).date().isoformat(), "zone": "UTC"})
        self.assertEqual(report["status"], "draft")
        self.assertAlmostEqual(report["coverage"], .9)
        self.assertAlmostEqual(report["total_score"], 100)
        self.assertIsNone(report["human_seconds"])
        self.assertIsNone(report["actual_spend_minor"])
        facts = report["breakdown"]["facts"]
        ai = [f for f in facts if f["track"] == "ai" and f["state"] == "known"]
        self.assertEqual(len(ai), 2, "two real attempts must remain distinct facts")
        self.assertEqual(len(report["breakdown"]["productivity"]["evidence"]["quality"]), 1)
        self.assertIn(job["id"], json.dumps(report["evidence_ids"]))
        self.evidence(job, adapter.native_session)

    def cancel_recovery(self, mode):
        plan, job = self.create()
        def cancel():
            current = self.job(job)
            self.api("POST", "/remote-jobs/" + job["id"] + "/commands", {
                "action": "cancel", "idempotency_key": uuid.uuid4().hex, "expected_revision": current["revision"]})
        self.transport.mode = mode
        self.assertIn("cancelled", self.agent(ExternalAI("cancel", cancel)).run_once())
        pending = self.db.pending_remote_events()
        if mode:
            self.assertTrue(self.transport.occurred)
            self.assertEqual(len(pending), 2)
        original = [r["payload"] for r in pending]
        self.db.close()
        self.db = Database(self.home / "runner.sqlite")
        self.assertEqual([r["payload"] for r in self.db.pending_remote_events()], original)
        self.transport.mode = None
        self.agent(ExternalAI()).flush_outbox()
        self.assertEqual(self.db.pending_remote_events(), [])
        self.assertEqual(self.job(job)["status"], "cancelled")
        claim = self.db.get_remote_claim(job["id"])
        with self.assertRaises(CloudError) as stale:
            self.cloud.append_events(self.runner["access_token"], job["id"], claim["attempt_id"], claim["lease_epoch"],
                                     [{"id": uuid.uuid4().hex, "seq": 3, "type": "completed", "observed_at": stamp()}])
        self.assertEqual(stale.exception.status, 409)
        self.assertEqual(self.plan(plan)["status"], "cancelled")
        _, following = self.create()
        self.assertIn("awaiting_review", self.agent(ExternalAI()).run_once())
        self.assertEqual(self.job(following)["status"], "awaiting_review")
        self.evidence(job)

    def test_cancel_rejects_old_events(self):
        self.cancel_recovery(None)

    def test_disconnect_outbox_survives_sqlite_restart(self):
        self.cancel_recovery("offline")

    def test_committed_response_loss_replays_same_events(self):
        self.cancel_recovery("lost_reply")

    def test_unknown_and_false_billing_block_claim(self):
        for billing in (None, False):
            with self.subTest(billing=billing):
                self.inventory(self.runner, billing)
                _, job = self.create()
                self.assertIsNone(self.cloud.claim(self.runner["access_token"]))
                self.assertEqual(self.job(job)["status"], "queued")

    def test_unknown_quota_still_dispatches(self):
        # A runner that never uploaded a quota sample: its pool reads unknown,
        # and unknown must not hold work back (spec 2026-09-25 §4.3).
        other = self.pair("runner-three")
        self.inventory(other)
        _, job = self.create(runner=other)
        agent = Agent(self.db, self.cloud, {"codex": ExternalAI("complete")}, self.home,
                      lambda: other["access_token"], heartbeat_interval=.02)
        outcome = agent.run_once()
        self.assertTrue(outcome.startswith("job "), outcome)
        self.assertEqual(self.job(job)["status"], "awaiting_review")

    def test_not_before_holds_the_job_until_due(self):
        due = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(minutes=5)
        _, job = self.create(not_before=stamp(due))
        self.assertEqual(job["not_before"], stamp(due))
        self.assertEqual(self.agent(ExternalAI("complete")).run_once(), "idle")
        self.assertEqual(self.job(job)["status"], "queued")

    def test_completed_job_carries_output_tail(self):
        class LoggingAI(ExternalAI):
            def start(self, prompt, cwd, session_id, log_file, cancel_event):
                Path(log_file).write_text("$ integration\n3 passed\n")
                return super().start(prompt, cwd, session_id, log_file, cancel_event)

        _, job = self.create()
        self.agent(LoggingAI("complete")).run_once()
        self.assertEqual(self.job(job).get("output_tail"), "$ integration\n3 passed\n")

    def test_multiple_runners_cannot_steal_or_double_claim(self):
        other = self.pair("runner-two")
        self.inventory(other)
        self.sample(other, "primary", 10)
        _, job = self.create()
        barrier = threading.Barrier(3)
        def claim(runner):
            barrier.wait()
            return self.cloud.claim(runner["access_token"])
        with ThreadPoolExecutor(max_workers=3) as workers:
            futures = [workers.submit(claim, r) for r in (self.runner, self.runner, other)]
            results = [f.result() for f in futures]
        claims = [r for r in results if r]
        self.assertEqual(len(claims), 1)
        self.assertEqual(claims[0]["job"]["id"], job["id"])
        self.assertIsNone(results[2])
        with self.assertRaises(CloudError) as foreign:
            self.cloud.renew(other["access_token"], claims[0]["attempt_id"], claims[0]["lease_epoch"])
        self.assertEqual(foreign.exception.status, 409)


if __name__ == "__main__":
    CONFIG.update(json.load(sys.stdin))
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WorkspaceFlowTests))
    print("workspace_tests=%d failures=%d errors=%d skip=%d" % (result.testsRun, len(result.failures), len(result.errors), len(result.skipped)), flush=True)
    sys.exit(0 if result.wasSuccessful() and not result.skipped else 1)
