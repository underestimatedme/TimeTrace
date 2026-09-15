import json
import tempfile
import threading
import time
import unittest
import subprocess
from pathlib import Path

from keji.agent import Agent
from keji.checkpoints import Checkpoint
from keji.db import Database
from keji.models import RunResult, Sample


def init_repo(path: Path) -> None:
    path.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=path, check=True)


class FakeCloud:
    def __init__(self):
        self.events = []
        self.quota_posts = []

    def post_quota_samples(self, token, samples):
        self.quota_posts.append((token, samples))
        return {"accepted": len(samples)}

    def claim(self, token):
        return {"job": {"id": "j1", "workspace_id": "ws1", "tool_profile_id": "codex-default", "prompt": "do it"},
                "attempt_id": "a1", "lease_epoch": 1}

    def append_events(self, token, job_id, attempt_id, epoch, events):
        self.events.extend(events)

    def renew(self, token, attempt_id, epoch):
        self.renewed = (attempt_id, epoch)
        return {}


class Adapter:
    def capabilities(self):
        # A verified subscription profile: zero additional spend guaranteed.
        return {"can_record": True, "can_read_quota": True, "can_dispatch": True,
                "can_resume": True, "can_enforce_zero_spend": True}

    def start(self, prompt, cwd, session_id, log_file, cancel_event=None):
        self.args = (prompt, cwd)
        return RunResult(exit_code=0, ok=True, output="finished", session_id=session_id)


class AgentTest(unittest.TestCase):
    def test_claim_is_persisted_before_execution_and_completed(self):
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"
            init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = FakeCloud(), Adapter()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → awaiting_review")
            self.assertEqual(adapter.args, ("do it", str(repo.resolve())))
            self.assertEqual([event["type"] for event in cloud.events], ["running", "completed"])
            self.assertEqual(db.get_remote_claim("j1")["state"], "reported")
            self.assertEqual(db.pending_remote_events(), [])

    def test_registered_default_branch_is_used(self):
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "release")
            bases = []
            agent = Agent(db, FakeCloud(), {"codex": Adapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (bases.append(base) or repo, "branch"))
            agent.run_once()
            self.assertEqual(bases, ["release"])

    def test_duplicate_running_claim_is_not_started_again(self):
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = FakeCloud(), Adapter()
            db.save_remote_claim(cloud.claim("token"), state="running")
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token")
            self.assertIn("duplicate", agent.run_once())
            self.assertFalse(hasattr(adapter, "args"))

    def test_long_run_renews_lease(self):
        class SlowAdapter(Adapter):
            def start(self, *args):
                time.sleep(.04)
                return super().start(*args)
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud = FakeCloud()
            agent = Agent(db, cloud, {"codex": SlowAdapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "branch"), heartbeat_interval=.01)
            agent.run_once()
            self.assertEqual(cloud.renewed, ("a1", 1))

    def test_cancel_command_stops_adapter_and_is_acknowledged(self):
        class CancelCloud(FakeCloud):
            def renew(self, token, attempt_id, epoch):
                return {"desired_action": "cancel"}
        class CancellableAdapter(Adapter):
            def start(self, prompt, cwd, session_id, log_file, cancel_event=None):
                self.cancelled = cancel_event.wait(.5)
                return RunResult(exit_code=143, ok=False, error="terminated")
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = CancelCloud(), CancellableAdapter()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "branch"), heartbeat_interval=.01)
            self.assertEqual(agent.run_once(), "job j1 → cancelled")
            self.assertTrue(adapter.cancelled)
            self.assertEqual(cloud.events[-1]["type"], "cancelled")

    def test_unknown_workspace_is_rejected_without_execution(self):
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            cloud = FakeCloud()
            agent = Agent(db, cloud, {"codex": Adapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → rejected (unknown workspace)")
            self.assertEqual(cloud.events[-1]["type"], "failed")

    def test_completion_survives_network_failure_in_outbox(self):
        class FlakyCloud(FakeCloud):
            def append_events(self, token, job_id, attempt_id, epoch, events):
                if events[0]["seq"] == 2 and not getattr(self, "recovered", False):
                    raise OSError("offline")
                super().append_events(token, job_id, attempt_id, epoch, events)
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"
            init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud = FlakyCloud()
            agent = Agent(db, cloud, {"codex": Adapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → awaiting_review")
            self.assertEqual([row["seq"] for row in db.pending_remote_events()], [2])
            cloud.recovered = True
            agent.flush_outbox()
            self.assertEqual(db.pending_remote_events(), [])
            self.assertEqual(cloud.events[-1]["type"], "completed")

    def test_unverified_billing_blocks_execution(self):
        class UnverifiedAdapter(Adapter):
            def capabilities(self):
                caps = super().capabilities()
                caps["can_enforce_zero_spend"] = False
                return caps

        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = FakeCloud(), UnverifiedAdapter()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → blocked (billing_unverified)")
            # The adapter must never have been started.
            self.assertFalse(hasattr(adapter, "args"))
            self.assertEqual(cloud.events[-1]["type"], "waiting_input")

    def test_malformed_capabilities_block_without_execution(self):
        def raising_capabilities():
            raise RuntimeError("unavailable")

        class MalformedAdapter:
            def __init__(self, capabilities):
                self.capabilities = capabilities
                self.calls = []

            def start(self, *args):
                self.calls.append("start")
                return RunResult(exit_code=0, ok=True)

            def resume(self, *args):
                self.calls.append("resume")
                return RunResult(exit_code=0, ok=True)

        for capabilities in (raising_capabilities, lambda: ["not a mapping"], {}):
            with self.subTest(capabilities=capabilities):
                with tempfile.TemporaryDirectory() as d:
                    db = Database(Path(d) / "keji.db")
                    repo = Path(d) / "repo"; init_repo(repo)
                    db.upsert_workspace("ws1", "repo", str(repo), "main")
                    cloud, adapter = FakeCloud(), MalformedAdapter(capabilities)
                    agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                                  prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
                    self.assertEqual(agent.run_once(), "job j1 → blocked (billing_unverified)")
                    self.assertEqual(adapter.calls, [])
                    self.assertEqual(db.get_remote_claim("j1")["state"], "reported")
                    self.assertEqual(cloud.events[-1]["type"], "waiting_input")

    def test_unverified_billing_blocks_resume_before_running(self):
        class UnverifiedResumingAdapter(Adapter):
            def __init__(self):
                self.calls = []

            def capabilities(self):
                caps = super().capabilities()
                caps["can_enforce_zero_spend"] = False
                return caps

            def resume(self, prompt, cwd, session_id, log_file, cancel_event=None):
                self.calls.append((prompt, cwd, session_id))
                return RunResult(exit_code=0, ok=True, session_id=session_id)

        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            db.save_checkpoint(Checkpoint(
                plan_id="j1", job_id="j1", attempt_id="a1", tool_profile_id="codex-default",
                provider_session_id="provider-session", canonical_workspace=str(repo), git_head="",
                dirty_paths_digest="", last_output_offset=0, completed_criteria=[],
                side_effect_summary="", reason="waiting_quota",
            ))
            cloud, adapter = FakeCloud(), UnverifiedResumingAdapter()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → blocked (billing_unverified)")
            self.assertEqual(adapter.calls, [])
            self.assertEqual(db.get_remote_claim("j1")["state"], "reported")
            self.assertEqual(cloud.events[-1]["type"], "waiting_input")

    def test_quota_block_checkpoints_then_resumes_same_session(self):
        class ReleasingCloud(FakeCloud):
            def __init__(self):
                super().__init__()
                self.n = 0

            def claim(self, token):
                self.n += 1
                c = super().claim(token)
                c["attempt_id"] = "a%d" % self.n  # each re-lease is a new attempt
                return c

        class BlockThenResume(Adapter):
            def __init__(self):
                self.calls = []

            def start(self, prompt, cwd, session_id, log_file, cancel_event=None):
                self.calls.append(("start", session_id))
                return RunResult(exit_code=1, blocked=True, error="usage limit", session_id="prov-sess")

            def resume(self, prompt, cwd, session_id, log_file, cancel_event=None):
                self.calls.append(("resume", session_id))
                return RunResult(exit_code=0, ok=True, output="done", session_id=session_id)

        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = ReleasingCloud(), BlockThenResume()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → waiting_quota")
            cp = db.get_checkpoint("j1")
            self.assertIsNotNone(cp)
            self.assertEqual(cp.provider_session_id, "prov-sess")
            # Natural recovery re-leases: the agent resumes the original session.
            self.assertEqual(agent.run_once(), "job j1 → awaiting_review")
            self.assertEqual(adapter.calls[0][0], "start")
            self.assertEqual(adapter.calls[1], ("resume", "prov-sess"))
            self.assertIsNone(db.get_checkpoint("j1"))  # cleared on completion

    def test_reports_quota_from_readable_adapters(self):
        class ReadingAdapter(Adapter):
            def read_limits(self):
                return [Sample(bucket_key="codex:weekly", tool="codex", used_pct=42.0,
                               reset_at=None, window_mins=10080, source="app-server")]

        class BlindAdapter(Adapter):
            def capabilities(self):
                caps = super().capabilities()
                caps["can_read_quota"] = False
                return caps

            def read_limits(self):
                raise AssertionError("must not read quota when incapable")

        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            cloud = FakeCloud()
            agent = Agent(db, cloud, {"codex": ReadingAdapter(), "claude": BlindAdapter()},
                          Path(d), lambda: "secrettoken")
            n = agent.report_quota(now=1000.0)
            self.assertEqual(n, 1)  # only the readable adapter reports
            token, samples = cloud.quota_posts[0]
            p = samples[0]
            self.assertEqual((p["kind"], p["scope"], p["used_percent"], p["pool_id"]),
                             ("codex", "weekly", 42.0, "pool-codex"))
            self.assertNotIn("secrettoken", json.dumps(p))
            self.assertNotIn("@", json.dumps(p))

    def test_quota_block_reports_exhaustion_sample(self):
        class BlockingAdapter(Adapter):
            def start(self, prompt, cwd, session_id, log_file, cancel_event=None):
                return RunResult(exit_code=1, blocked=True, error="usage limit", session_id="s",
                                 samples=[Sample(bucket_key="codex:weekly", tool="codex",
                                                 used_pct=100.0, reset_at=None, window_mins=10080)])

        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud = FakeCloud()
            agent = Agent(db, cloud, {"codex": BlockingAdapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → waiting_quota")
            self.assertEqual(len(cloud.quota_posts), 1)
            self.assertEqual(cloud.quota_posts[0][1][0]["used_percent"], 100.0)

    def test_workspace_busy_defers_without_second_run(self):
        from keji.dispatch import workspace_lock

        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"; init_repo(repo)
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = FakeCloud(), Adapter()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home, base: (repo, "keji/test"))
            # Another process already writing this canonical workspace.
            held = workspace_lock(Path(d), str(repo)).acquire()
            try:
                self.assertEqual(agent.run_once(), "job j1 → deferred (workspace busy)")
                self.assertFalse(hasattr(adapter, "args"))
            finally:
                held.release()


if __name__ == "__main__":
    unittest.main()
