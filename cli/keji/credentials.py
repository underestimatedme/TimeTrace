"""Runner credentials stored in the macOS login Keychain."""
import json
import subprocess
import time
from typing import Any, Callable, Dict, Optional


class CredentialStore:
    SERVICE = "com.atlaspaces.keji.runner"

    def __init__(self, runner: Callable = subprocess.run):
        self.runner = runner

    def save(self, credentials: Dict[str, Any]) -> None:
        self.runner([
            "security", "add-generic-password", "-U", "-s", self.SERVICE,
            "-a", "default", "-w", json.dumps(credentials, separators=(",", ":")),
        ], check=True, capture_output=True, text=True)

    def load(self, account: str = "default") -> Optional[Dict[str, Any]]:
        result = self.runner([
            "security", "find-generic-password", "-s", self.SERVICE, "-a", account, "-w",
        ], check=False, capture_output=True, text=True)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)

    def delete(self, account: str = "default") -> None:
        self.runner([
            "security", "delete-generic-password", "-s", self.SERVICE, "-a", account,
        ], check=False, capture_output=True, text=True)


class SessionManager:
    def __init__(self, store: CredentialStore, cloud: Any, clock: Callable[[], float] = time.time):
        self.store, self.cloud, self.clock = store, cloud, clock
        self.credentials = store.load()

    def token(self) -> str:
        if not self.credentials:
            raise RuntimeError("computer is not paired; run `keji cloud login`")
        if int(self.credentials.get("expires_at") or 0) <= int(self.clock()) + 30:
            refreshed = self.cloud.refresh(self.credentials["refresh_token"])
            refreshed["expires_at"] = int(self.clock()) + int(refreshed.get("expires_in") or 900)
            self.store.save(refreshed)
            self.credentials = refreshed
        return str(self.credentials["access_token"])
