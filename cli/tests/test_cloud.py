import json
import unittest

from keji.cloud import CloudClient, CloudError


class Response:
    def __init__(self, status, body):
        self.status = status
        self.body = json.dumps(body).encode()

    def read(self):
        return self.body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class CloudClientTest(unittest.TestCase):
    def test_envelope_and_bearer(self):
        seen = []

        def opener(request, timeout):
            seen.append(request)
            return Response(200, {"code": 0, "message": "ok", "data": {"status": "pending"}})

        client = CloudClient("https://valley.example/timetrace/api/v1", opener=opener)
        data = client.request("POST", "/runner/jobs/claim", {"wait_seconds": 0}, token="secret")
        self.assertEqual(data["status"], "pending")
        self.assertEqual(seen[0].get_header("Authorization"), "Bearer secret")

    def test_nonzero_envelope_raises(self):
        client = CloudClient("https://v", opener=lambda req, timeout: Response(200, {"code": 40900, "message": "conflict"}))
        with self.assertRaises(CloudError):
            client.request("GET", "/x")

    def test_renew_uses_attempt_endpoint(self):
        seen = []
        client = CloudClient("https://v", opener=lambda req, timeout: (seen.append(req) or Response(200, {"code": 0, "data": {}})))
        client.renew("token", "a1", 3)
        self.assertTrue(seen[0].full_url.endswith("/runner/attempts/a1/renew"))

    def test_events_use_attempt_endpoint(self):
        seen = []
        client = CloudClient("https://v", opener=lambda req, timeout: (seen.append(req) or Response(200, {"code": 0, "data": {}})))
        client.append_events("token", "j1", "a1", 3, [{"seq": 1, "type": "running"}])
        self.assertTrue(seen[0].full_url.endswith("/runner/attempts/a1/events"))

    def test_quota_samples_endpoint_and_body(self):
        seen = []

        def opener(request, timeout):
            seen.append(request)
            return Response(200, {"code": 0, "data": {"accepted": 1}})

        client = CloudClient("https://v", opener=opener)
        payload = [{"sample_id": "s1", "pool_id": "pool-1", "used_percent": 20.0}]
        client.post_quota_samples("secrettoken", payload)
        self.assertTrue(seen[0].full_url.endswith("/runner/quota/samples"))
        body = json.loads(seen[0].data.decode())
        self.assertEqual(body, {"samples": payload})
        # The sample body itself must not carry credentials or account emails.
        raw = seen[0].data.decode()
        for leak in ("secrettoken", "refresh", "@"):
            self.assertNotIn(leak, raw)


if __name__ == "__main__":
    unittest.main()
