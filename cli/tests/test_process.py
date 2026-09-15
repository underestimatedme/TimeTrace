import os
import sys
import tempfile
import time
import unittest
import threading
from pathlib import Path

from keji.process import run_streaming


class ProcessTest(unittest.TestCase):
    def test_already_cancelled_run_never_creates_a_process(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "spawned"
            cancelled = threading.Event()
            cancelled.set()
            with self.assertRaisesRegex(RuntimeError, "cancelled"):
                run_streaming([sys.executable, "-c", "from pathlib import Path; Path(%r).touch()" % str(marker)],
                              d, str(Path(d) / "run.log"), cancel_event=cancelled)
            self.assertFalse(marker.exists())

    def test_drains_stderr_without_deadlock(self):
        with tempfile.TemporaryDirectory() as d:
            log = str(Path(d) / "run.log")
            script = "import sys; sys.stderr.write('x'*200000); print('done')"
            code, lines = run_streaming([sys.executable, "-c", script], d, log, timeout=5)
            self.assertEqual(code, 0)
            self.assertEqual(lines, ["done"])
            self.assertGreater(os.path.getsize(log), 200000)

    def test_timeout_kills_process_group(self):
        with tempfile.TemporaryDirectory() as d:
            started = time.monotonic()
            code, _ = run_streaming(
                [sys.executable, "-c", "import time; time.sleep(30)"], d,
                str(Path(d) / "run.log"), timeout=0.2,
            )
            self.assertLess(time.monotonic() - started, 3)
            self.assertNotEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
