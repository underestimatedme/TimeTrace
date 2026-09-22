"""Invoked by the Go fixture against real local Valley HTTP + PostgreSQL."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from keji.agent import Agent
from keji.cloud import CloudClient
from keji.db import Database
from keji.models import RunResult


def main():
    config = json.load(sys.stdin)
    assert config["url"].startswith("http://127.0.0.1:"), "local fixture only"
    class Transport(CloudClient):
        dropped = False
        deliveries = []
        def append_events(self, token, job, attempt, epoch, events):
            result = super().append_events(token, job, attempt, epoch, events)
            self.deliveries.append(json.loads(json.dumps(events)))
            if config["lost_reply"] and not self.dropped and any(e["type"] == "cancelled" for e in events):
                self.dropped = True
                raise OSError("server committed; reply lost")
            return result
    cloud = Transport(config["url"])
    class Adapter:
        calls = 0
        def capabilities(self):
            return {"can_dispatch": True, "can_resume": True, "can_enforce_zero_spend": True}
        def start(self, prompt, cwd, session_id, log_file, cancel_event):
            self.calls += 1
            if self.calls == 1:
                # This owner command really reaches Valley while the adapter
                # is running; the next real HTTP renewal observes cancellation.
                job = cloud.request("GET", "/remote-jobs/" + config["first"], token=config["owner"])
                cloud.request("POST", "/remote-jobs/" + job["id"] + "/commands", {
                    "action": "cancel", "idempotency_key": "cancel-live", "expected_revision": job["revision"],
                }, config["owner"])
                assert cancel_event.wait(5), "runner did not observe server cancellation"
                return RunResult(exit_code=143, error="cancelled")
            return RunResult(exit_code=0, ok=True, output="next job completed")
    with tempfile.TemporaryDirectory(prefix="f09-r3-runner-") as directory:
        home = Path(directory)
        repo = home / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
        subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "initial"], cwd=repo, check=True)
        path = home / "runner.db"
        db = Database(path)
        db.upsert_workspace("ws1", "fixture", str(repo), "main")
        adapter = Adapter()
        def agent():
            return Agent(db, cloud, {"codex": adapter}, home, lambda: config["runner"],
                         prepare_workspace=lambda *args: (str(repo), "main"), heartbeat_interval=.02)
        outcome = agent().run_once()
        assert outcome == "job %s → cancelled" % config["first"], outcome
        job = cloud.request("GET", "/remote-jobs/" + config["first"], token=config["owner"])
        assert job["status"] == "cancelled", job
        original = [json.loads(row[0]) for row in db.conn.execute("SELECT payload FROM remote_outbox WHERE job_id=? ORDER BY seq", (config["first"],))]
        pending = db.pending_remote_events()
        assert [row["payload"] for row in pending] == (original if config["lost_reply"] else []), pending
        db.close()
        db = Database(path)  # actual restart recovery, not an in-memory retry
        assert agent().run_once() == "job %s → awaiting_review" % config["second"]
        assert db.pending_remote_events() == []
        if config["lost_reply"]:
            assert cloud.deliveries[0] == cloud.deliveries[1] == original
        db.close()
        print(json.dumps({"events": original}))


if __name__ == "__main__":
    main()
