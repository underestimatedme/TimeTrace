import unittest

from keji.adapters.cursor import CursorAdapter, safe_capabilities
from keji.adapters.gemini import GeminiAdapter


class CapabilitiesTest(unittest.TestCase):
    def test_management_only_default(self):
        result = safe_capabilities()
        self.assertTrue(result["can_record"])
        self.assertFalse(result["can_dispatch"])
        self.assertFalse(result["can_enforce_zero_spend"])

    def test_adapters_are_management_only(self):
        for adapter in (CursorAdapter({}), GeminiAdapter({})):
            caps = adapter.capabilities()
            self.assertEqual(set(caps), {"can_record", "can_read_quota", "can_dispatch",
                                         "can_resume", "can_enforce_zero_spend"})
            self.assertTrue(caps["can_record"])
            self.assertFalse(caps["can_dispatch"])
            self.assertFalse(caps["can_resume"])
            self.assertFalse(caps["can_enforce_zero_spend"])
            self.assertTrue(adapter.adapter_version)

    def test_no_faked_start_or_resume(self):
        # An unverified tool must not pretend to dispatch or resume.
        with self.assertRaises(NotImplementedError):
            CursorAdapter({}).start("prompt", "/tmp", "sess", "log")
        with self.assertRaises(NotImplementedError):
            GeminiAdapter({}).resume("prompt", "/tmp", "sess", "log")


if __name__ == "__main__":
    unittest.main()
