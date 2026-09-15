import subprocess
import tempfile
import unittest
from pathlib import Path

from keji import worktree


def git(*args, cwd):
    return subprocess.run(["git"] + list(args), cwd=cwd, check=True, capture_output=True,
                          text=True).stdout.strip()


class WorktreeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.home = root / "home"
        self.repo.mkdir()
        git("init", "-q", "-b", "main", cwd=self.repo)
        git("config", "user.email", "t@example.com", cwd=self.repo)
        git("config", "user.name", "t", cwd=self.repo)
        (self.repo / "README.md").write_text("hi\n")
        git("add", ".", cwd=self.repo)
        git("commit", "-q", "-m", "init", cwd=self.repo)
        git("remote", "add", "origin", "https://example.com/x.git", cwd=self.repo)

    def tearDown(self):
        self.tmp.cleanup()

    def test_ensure_creates_isolated_worktree_with_push_blocked(self):
        path, branch = worktree.ensure(str(self.repo), 1, self.home)
        self.assertEqual(branch, "keji/1")
        self.assertTrue((Path(path) / "README.md").exists())
        self.assertEqual(git("rev-parse", "--abbrev-ref", "HEAD", cwd=path), "keji/1")
        self.assertEqual(git("config", "remote.origin.pushurl", cwd=path), "no_push://blocked")
        # main checkout keeps its normal push url
        r = subprocess.run(["git", "config", "remote.origin.pushurl"], cwd=self.repo,
                           capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        # push from the worktree must fail fast
        r = subprocess.run(["git", "push", "origin", "keji/1"], cwd=path, capture_output=True,
                           text=True)
        self.assertNotEqual(r.returncode, 0)

    def test_ensure_is_idempotent(self):
        p1, _ = worktree.ensure(str(self.repo), 2, self.home)
        p2, _ = worktree.ensure(str(self.repo), 2, self.home)
        self.assertEqual(p1, p2)

    def test_ensure_can_start_from_another_task_branch(self):
        p1, b1 = worktree.ensure(str(self.repo), 1, self.home)
        (Path(p1) / "step1.txt").write_text("one\n")
        git("add", ".", cwd=p1)
        git("commit", "-q", "-m", "step 1", cwd=p1)
        p2, b2 = worktree.ensure(str(self.repo), 2, self.home, base=b1)
        self.assertTrue((Path(p2) / "step1.txt").exists())
        self.assertEqual(git("rev-parse", "--abbrev-ref", "HEAD", cwd=p2), "keji/2")
        with self.assertRaisesRegex(ValueError, "base branch"):
            worktree.ensure(str(self.repo), 3, self.home, base="keji/does-not-exist")

    def test_is_git_repo(self):
        self.assertTrue(worktree.is_git_repo(str(self.repo)))
        self.assertFalse(worktree.is_git_repo(self.tmp.name))

    def test_snapshot_detects_assume_unchanged_tracked_bytes(self):
        git("update-index", "--assume-unchanged", "README.md", cwd=self.repo)
        before = worktree.snapshot(str(self.repo))
        (self.repo / "README.md").write_text("changed while hidden from git diff\n")
        self.assertNotEqual(worktree.snapshot(str(self.repo)), before)


if __name__ == "__main__":
    unittest.main()
