import base64
import json
import tempfile
import unittest
from pathlib import Path

from keji import tiers


def jwt_with(claims):
    seg = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return "hdr." + seg + ".sig"


class TierTest(unittest.TestCase):
    def test_codex_plan_from_id_token(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "auth.json"
            p.write_text(json.dumps({"tokens": {"id_token": jwt_with({"https://api.openai.com/auth": {"chatgpt_plan_type": "Plus"}})}}))
            self.assertEqual(tiers.codex_plan_tier(p), "plus")

    def test_codex_missing_or_malformed_is_none(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(tiers.codex_plan_tier(Path(d) / "missing.json"))
            p = Path(d) / "auth.json"
            p.write_text(json.dumps({"tokens": {"id_token": "not-a-jwt"}}))
            self.assertIsNone(tiers.codex_plan_tier(p))
            p.write_text("{not json")
            self.assertIsNone(tiers.codex_plan_tier(p))

    def test_claude_subscription_type_from_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / ".credentials.json"
            p.write_text(json.dumps({"claudeAiOauth": {"accessToken": "secret", "subscriptionType": "max"}}))
            self.assertEqual(tiers.claude_plan_tier(p), "max")
            self.assertIsNone(tiers.claude_plan_tier(Path(d) / "nope.json", keychain=lambda: None))

    def test_claude_falls_back_to_keychain_when_file_is_absent(self):
        with tempfile.TemporaryDirectory() as d:
            secret = json.dumps({"claudeAiOauth": {"accessToken": "secret", "subscriptionType": "pro"}})
            self.assertEqual(tiers.claude_plan_tier(Path(d) / "nope.json", keychain=lambda: secret), "pro")
            self.assertIsNone(tiers.claude_plan_tier(Path(d) / "nope.json", keychain=lambda: "{broken"))

    def test_tier_strings_never_carry_tokens(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / ".credentials.json"
            p.write_text(json.dumps({"claudeAiOauth": {"accessToken": "sk-ant-secret", "subscriptionType": " Max "}}))
            self.assertEqual(tiers.claude_plan_tier(p), "max")
