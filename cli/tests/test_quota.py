import unittest

from keji.quota import (
    Window,
    availability,
    default_capabilities,
    make_window,
    merge_capabilities,
    sample_payload,
)


class QuotaTest(unittest.TestCase):
    def test_unknown_and_multi_window(self):
        self.assertEqual(availability([], 200), "unknown")
        # A window that has already expired is unknown, never treated as full.
        self.assertEqual(availability([Window(100, 100, 50, 150)], 200), "unknown")
        # Weekly exhausted dominates a fresh, available short window.
        windows = [Window(0, 300, 190, 250), Window(100, 900, 190, 250)]
        self.assertEqual(availability(windows, 200), "blocked")

    def test_all_fresh_available(self):
        windows = [Window(20, 300, 190, 250), Window(40, 900, 190, 250)]
        self.assertEqual(availability(windows, 200), "available")

    def test_nil_reading_is_unknown(self):
        windows = [Window(20, 300, 190, 250), Window(None, 900, 190, 250)]
        self.assertEqual(availability(windows, 200), "unknown")

    def test_partial_freshness_is_unknown(self):
        # One fresh, one stale -> not all applicable windows are fresh.
        windows = [Window(10, 300, 190, 250), Window(10, 300, 10, 150)]
        self.assertEqual(availability(windows, 200), "unknown")


class WindowParseTest(unittest.TestCase):
    def test_rejects_out_of_range(self):
        for bad in (-1, 101, float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                make_window(bad, None, 100, 200)

    def test_expires_not_after_reset(self):
        # A freshness horizon cannot outlive a trusted reset boundary.
        w = make_window(50, 150, 100, 300)
        self.assertEqual(w.expires_at, 150)

    def test_requires_positive_window(self):
        with self.assertRaises(ValueError):
            make_window(50, None, 200, 200)


class CapabilityTest(unittest.TestCase):
    def test_defaults_all_false(self):
        caps = default_capabilities()
        self.assertEqual(set(caps.values()), {False})
        self.assertFalse(caps["can_enforce_zero_spend"])

    def test_merge_only_known_keys(self):
        caps = merge_capabilities({"can_record": True, "bogus": True})
        self.assertTrue(caps["can_record"])
        self.assertNotIn("bogus", caps)
        # A manual/source claim cannot grant the billing-safety capability.
        self.assertFalse(caps["can_enforce_zero_spend"])


class SamplePayloadTest(unittest.TestCase):
    def test_payload_carries_no_secrets(self):
        w = make_window(30, None, 190, 250)
        payload = sample_payload("sid", "pool-1", "cli-a", "short", "codex", w,
                                 source="runner", confidence="exact")
        self.assertEqual(payload["pool_id"], "pool-1")
        self.assertEqual(payload["used_percent"], 30.0)
        # RFC3339 timestamps, opaque ids only; no tokens/emails/env.
        allowed = {"sample_id", "pool_id", "profile_id", "scope", "kind",
                   "used_percent", "reset_at", "observed_at", "expires_at",
                   "source", "confidence"}
        self.assertEqual(set(payload), allowed)
        self.assertTrue(payload["observed_at"].endswith("Z"))


class AdapterCapabilityTest(unittest.TestCase):
    def test_adapters_declare_conservative_capabilities(self):
        from keji.adapters.claude import ClaudeAdapter
        from keji.adapters.codex import CodexAdapter

        for adapter in (ClaudeAdapter({}), CodexAdapter({})):
            caps = adapter.capabilities()
            self.assertEqual(set(caps), set(default_capabilities()))
            self.assertTrue(caps["can_record"])
            # Billing-safety capability stays unverified until R4 checks it,
            # so unattended resume is not authorised on the adapter alone.
            self.assertFalse(caps["can_enforce_zero_spend"])
            self.assertTrue(adapter.adapter_version)

        self.assertFalse(ClaudeAdapter({}).capabilities()["can_read_quota"])
        self.assertTrue(CodexAdapter({}).capabilities()["can_read_quota"])


if __name__ == "__main__":
    unittest.main()
