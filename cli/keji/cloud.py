"""Small Valley HTTP client using only the Python standard library."""
import json
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, Optional


class CloudError(RuntimeError):
    def __init__(self, message: str, status: int = 0, code: int = 0):
        super().__init__(message)
        self.status = status
        self.code = code


class CloudClient:
    def __init__(self, base_url: str, opener: Optional[Callable] = None, timeout: int = 30):
        self.base_url = base_url.rstrip("/")
        self.opener = opener or urllib.request.urlopen
        self.timeout = timeout

    def request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None,
                token: Optional[str] = None) -> Any:
        payload = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(self.base_url + path, data=payload, method=method)
        request.add_header("Accept", "application/json")
        if payload is not None:
            request.add_header("Content-Type", "application/json")
        if token:
            request.add_header("Authorization", "Bearer " + token)
        try:
            with self.opener(request, timeout=self.timeout) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as exc:
            status, raw = exc.code, exc.read()
        if status == 204:
            return None
        try:
            envelope = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as exc:
            raise CloudError("invalid Valley response", status=status) from exc
        if status >= 400 or envelope.get("code") != 0:
            raise CloudError(envelope.get("message") or "Valley request failed", status, int(envelope.get("code") or 0))
        return envelope.get("data")

    def create_device_authorization(self, name: str, platform: str, version: str) -> Dict[str, Any]:
        return self.request("POST", "/device-authorizations", {
            "device_name": name, "platform": platform, "client_version": version,
        })

    def poll_device_authorization(self, device_code: str) -> Dict[str, Any]:
        return self.request("POST", "/device-authorizations/token", {"device_code": device_code})

    def activate(self, device_code: str, activation_code: str) -> Dict[str, Any]:
        return self.request("POST", "/device-authorizations/activate", {
            "device_code": device_code, "activation_code": activation_code,
        })

    def refresh(self, refresh_token: str, idempotency_key: str) -> Dict[str, Any]:
        return self.request("POST", "/runner-auth/refresh", {
            "refresh_token": refresh_token, "idempotency_key": idempotency_key,
        })

    def update_inventory(self, token: str, workspaces: list, tools: list) -> Dict[str, Any]:
        return self.request("PUT", "/runner/inventory", {"workspaces": workspaces, "tools": tools}, token)

    def post_quota_samples(self, token: str, samples: list) -> Dict[str, Any]:
        """Send de-identified quota readings to Valley (dedup by sample_id).
        The payload carries only opaque pool/profile ids — never credentials."""
        return self.request("POST", "/runner/quota/samples", {"samples": samples}, token)

    def claim(self, token: str) -> Optional[Dict[str, Any]]:
        return self.request("POST", "/runner/jobs/claim", {"wait_seconds": 0}, token)

    def append_events(self, token: str, job_id: str, attempt_id: str, epoch: int, events: list) -> Dict[str, Any]:
        return self.request("POST", "/runner/attempts/%s/events" % attempt_id, {
			"job_id": job_id, "lease_epoch": epoch, "events": events,
        }, token)

    def renew(self, token: str, attempt_id: str, epoch: int) -> Dict[str, Any]:
        return self.request("POST", "/runner/attempts/%s/renew" % attempt_id, {
            "lease_epoch": epoch,
        }, token)
