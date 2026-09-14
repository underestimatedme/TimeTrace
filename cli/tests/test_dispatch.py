import tempfile
import unittest
from pathlib import Path

from keji.dispatch import (
    DispatchGate,
    FileLock,
    LockBusy,
    coding_slot_lock,
    deny_reason,
    workspace_lock,
)


class DispatchGateTest(unittest.TestCase):
    def test_all_clear(self):
        gate = DispatchGate(cancelled=False, lease_valid=True, runner_online=True,
                            dependencies_ready=True, zero_spend_verified=True)
        self.assertIsNone(deny_reason(gate))

    def test_no_billing_guarantee(self):
        gate = DispatchGate(False, True, True, True, False)
        self.assertEqual(deny_reason(gate), "billing_unverified")

    def test_cancel_wins(self):
        # Cancellation dominates every other signal.
        gate = DispatchGate(True, True, True, True, True)
        self.assertEqual(deny_reason(gate), "cancelled")

    def test_cancel_beats_expired_lease(self):
        gate = DispatchGate(True, False, True, True, True)
        self.assertEqual(deny_reason(gate), "cancelled")

    def test_ordered_reasons(self):
        self.assertEqual(deny_reason(DispatchGate(False, False, True, True, True)), "lease_expired")
        self.assertEqual(deny_reason(DispatchGate(False, True, False, True, True)), "runner_offline")
        self.assertEqual(deny_reason(DispatchGate(False, True, True, False, True)), "dependencies_pending")


class FileLockTest(unittest.TestCase):
    def test_second_acquire_is_denied(self):
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d) / "x.lock")
            first = FileLock(path).acquire()
            try:
                with self.assertRaises(LockBusy):
                    FileLock(path).acquire()
            finally:
                first.release()
            # After release the lock is free again.
            again = FileLock(path).acquire()
            again.release()

    def test_workspace_lock_is_per_canonical_path(self):
        with tempfile.TemporaryDirectory() as home:
            with tempfile.TemporaryDirectory() as ws1, tempfile.TemporaryDirectory() as ws2:
                a = workspace_lock(home, ws1).acquire()
                try:
                    # A different workspace is not blocked by the first lock.
                    b = workspace_lock(home, ws2).acquire()
                    b.release()
                    # The same workspace is blocked.
                    with self.assertRaises(LockBusy):
                        workspace_lock(home, ws1).acquire()
                finally:
                    a.release()

    def test_coding_slot_is_singleton(self):
        with tempfile.TemporaryDirectory() as home:
            slot = coding_slot_lock(home).acquire()
            try:
                with self.assertRaises(LockBusy):
                    coding_slot_lock(home).acquire()
            finally:
                slot.release()


if __name__ == "__main__":
    unittest.main()
