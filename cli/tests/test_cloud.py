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


if __name__ == "__main__":
    unittest.main()
