import tempfile
import unittest
from pathlib import Path

from keji.agent import Agent
from keji.db import Database
from keji.models import RunResult


class FakeCloud:
    def __init__(self):
        self.events = []

    def claim(self, token):
        return {"job": {"id": "j1", "workspace_id": "ws1", "tool_profile_id": "codex-default", "prompt": "do it"},
                "attempt_id": "a1", "lease_epoch": 1}

    def append_events(self, token, job_id, attempt_id, epoch, events):
        self.events.extend(events)


class Adapter:
    def start(self, prompt, cwd, session_id, log_file):
        self.args = (prompt, cwd)
        return RunResult(exit_code=0, ok=True, output="finished", session_id=session_id)


class AgentTest(unittest.TestCase):
    def test_claim_is_persisted_before_execution_and_completed(self):
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            repo = Path(d) / "repo"
            repo.mkdir()
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud, adapter = FakeCloud(), Adapter()
            agent = Agent(db, cloud, {"codex": adapter}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → awaiting_review")
            self.assertEqual(adapter.args, ("do it", str(repo.resolve())))
            self.assertEqual([event["type"] for event in cloud.events], ["running", "completed"])
            self.assertEqual(db.get_remote_claim("j1")["state"], "reported")
            self.assertEqual(db.pending_remote_events(), [])

    def test_unknown_workspace_is_rejected_without_execution(self):
        with tempfile.TemporaryDirectory() as d:
            db = Database(Path(d) / "keji.db")
            cloud = FakeCloud()
            agent = Agent(db, cloud, {"codex": Adapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home: (repo, "keji/test"))
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
            repo.mkdir()
            db.upsert_workspace("ws1", "repo", str(repo), "main")
            cloud = FlakyCloud()
            agent = Agent(db, cloud, {"codex": Adapter()}, Path(d), lambda: "token",
                          prepare_workspace=lambda repo, task_id, home: (repo, "keji/test"))
            self.assertEqual(agent.run_once(), "job j1 → awaiting_review")
            self.assertEqual([row["seq"] for row in db.pending_remote_events()], [2])
            cloud.recovered = True
            agent.flush_outbox()
            self.assertEqual(db.pending_remote_events(), [])
            self.assertEqual(cloud.events[-1]["type"], "completed")


if __name__ == "__main__":
    unittest.main()
