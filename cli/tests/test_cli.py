import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from keji import cli


def git(*args, cwd):
    subprocess.run(["git"] + list(args), cwd=cwd, check=True, capture_output=True)


class CliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.repo = root / "repo"
        self.repo.mkdir()
        git("init", "-q", cwd=self.repo)
        git("config", "user.email", "t@example.com", cwd=self.repo)
        git("config", "user.name", "t", cwd=self.repo)
        (self.repo / "a").write_text("a")
        git("add", ".", cwd=self.repo)
        git("commit", "-q", "-m", "init", cwd=self.repo)
        self._old = os.environ.get("KEJI_HOME")
        os.environ["KEJI_HOME"] = str(self.home)

    def tearDown(self):
        if self._old is None:
            os.environ.pop("KEJI_HOME", None)
        else:
            os.environ["KEJI_HOME"] = self._old
        self.tmp.cleanup()

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = cli.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_add_then_ls(self):
        code, out, _ = self.run_cli("add", "fix things", "--repo", str(self.repo), "--tool", "claude",
                                    "--priority", "2")
        self.assertEqual(code, 0)
        self.assertIn("task 1 added (runnable)", out)
        code, out, _ = self.run_cli("add", "then test", "--repo", str(self.repo), "--after", "1",
                                    "--any-tool")
        self.assertIn("task 2 added (pending)", out)
        code, out, _ = self.run_cli("ls")
        self.assertEqual(code, 0)
        self.assertIn("fix things", out)
        self.assertIn("after #1", out)
        code, out, _ = self.run_cli("ls", "--json")
        tasks = json.loads(out)
        self.assertEqual(tasks[0]["priority"], 2)
        self.assertEqual(tasks[1]["any_tool"], 1)
        self.assertEqual(tasks[1]["repo"], os.path.abspath(str(self.repo)))

    def test_doctor_diagnoses_persistent_lock_without_clearing_it(self):
        path = self.home / "locks" / "coding-slot.lock"
        path.parent.mkdir(parents=True)
        path.write_text("1234")
        with patch("keji.cli.CredentialStore") as credentials:
            credentials.return_value.load.return_value = None
            code, out, err = self.run_cli("agent", "doctor")
        self.assertIn("manual", out)
        self.assertIn(str(path), out)
        self.assertIn("descendants", out)
        self.assertEqual(path.read_text(), "1234")

    def test_add_rejects_non_repo_and_missing_dependency(self):
        code, _, err = self.run_cli("add", "x", "--repo", self.tmp.name)
        self.assertEqual(code, 2)
        self.assertIn("git repository", err)
        code, _, err = self.run_cli("add", "x", "--repo", str(self.repo), "--after", "99")
        self.assertEqual(code, 2)
        self.assertIn("no such task", err)

    def test_add_respects_allowed_repos(self):
        self.home.mkdir(parents=True)
        (self.home / "config.json").write_text(json.dumps({"allowed_repos": ["/nowhere"]}))
        code, _, err = self.run_cli("add", "x", "--repo", str(self.repo))
        self.assertEqual(code, 2)
        self.assertIn("allowed_repos", err)
        (self.home / "config.json").write_text(json.dumps({"allowed_repos": [self.tmp.name]}))
        code, out, _ = self.run_cli("add", "x", "--repo", str(self.repo))
        self.assertEqual(code, 0)

    def test_retry_rm_and_events(self):
        self.run_cli("add", "x", "--repo", str(self.repo))
        code, _, err = self.run_cli("retry", "1")
        self.assertEqual(code, 1)  # runnable tasks cannot be retried
        code, out, _ = self.run_cli("rm", "1")
        self.assertEqual(code, 0)
        code, out, _ = self.run_cli("ls")
        self.assertIn("no tasks", out)
        code, out, _ = self.run_cli("events")
        self.assertEqual(code, 0)
        self.assertIn("no events", out)
        code, _, err = self.run_cli("logs", "1")
        self.assertEqual(code, 1)

    def test_status_with_no_samples_and_broken_codex(self):
        self.home.mkdir(parents=True)
        (self.home / "config.json").write_text(json.dumps({"codex": {"bin": "/nonexistent/codex"}}))
        code, out, err = self.run_cli("status")
        self.assertEqual(code, 0)
        self.assertIn("no samples yet", out)
        self.assertIn("live Codex quota read failed", err)
        code, out, _ = self.run_cli("events", "--type", "sample_failure")
        self.assertIn("sample_failure", out)

    def test_statusline_ingests_interactive_rate_limits(self):
        self.home.mkdir(parents=True)
        (self.home / "config.json").write_text(json.dumps({"codex": {"bin": "/nonexistent/codex"}}))
        doc = {"session_id": "s", "model": {"id": "claude-haiku-4-5"}, "version": "2.1.258",
               "rate_limits": {"five_hour": {"used_percentage": 14.0, "resets_at": 1788370200},
                               "seven_day": {"used_percentage": 3, "resets_at": 1788552000}}}
        old_stdin = sys.stdin
        sys.stdin = io.StringIO(json.dumps(doc))
        try:
            code, out, _ = self.run_cli("statusline")
        finally:
            sys.stdin = old_stdin
        self.assertEqual(code, 0)
        self.assertIn("5h 86%", out)
        self.assertIn("7d 97%", out)
        code, out, _ = self.run_cli("status", "--json")
        data = json.loads(out)
        by_key = {b["bucket_key"]: b for b in data["buckets"]}
        self.assertEqual(by_key["claude:five_hour"]["used_pct"], 14.0)
        self.assertEqual(by_key["claude:five_hour"]["source"], "statusline")
        self.assertTrue(by_key["claude:five_hour"]["is_representative"])
        # a statusline payload without rate_limits (before the first response) is harmless
        sys.stdin = io.StringIO(json.dumps({"session_id": "s"}))
        try:
            code, out, _ = self.run_cli("statusline")
        finally:
            sys.stdin = old_stdin
        self.assertEqual(code, 0)
        self.assertIn("keji ·", out)

    def test_run_once_with_no_tasks_is_idle(self):
        self.home.mkdir(parents=True)
        (self.home / "config.json").write_text(json.dumps({"codex": {"bin": "/nonexistent/codex"},
                                                          "claude": {"bin": "/nonexistent/claude"}}))
        code, out, _ = self.run_cli("run", "--once")
        self.assertEqual(code, 0)
        self.assertIn("daemon", out)


if __name__ == "__main__":
    unittest.main()
