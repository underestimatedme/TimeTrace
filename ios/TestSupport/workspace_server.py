"""Local HTTP contract fixture: python3 TestSupport/workspace_server.py.

No production credentials or services. UI actions use the production HTTP stack.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NOW = "2026-09-15T10:00:00Z"
states = {}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def handle_request(self):
        parts = self.path.strip("/").split("/")
        scenario, path = parts[0], "/" + "/".join(parts[1:])
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or "{}")
        state = states.setdefault(scenario, {"tasks": [], "projects": [], "goals": [], "plans": {}, "jobs": {}})
        data, status, code = {}, 200, 0
        if path == "/auth/guest" or path == "/auth/refresh":
            data = {"access_token": "local-test", "refresh_token": "local-refresh", "expires_in": 900}
        elif path == "/runners":
            data = [{"runner": {"id": "runner-ui", "name": "Test Mac", "platform": "darwin", "client_version": "1",
                                "status": "online", "created_at": NOW, "updated_at": NOW},
                     "workspaces": [{"id": "workspace-ui", "name": "Test workspace", "enabled": True,
                                     "default_branch": "main", "updated_at": NOW}],
                     "tools": [{"id": "tool-ui", "provider": "codex", "version": "1", "status": "available", "updated_at": NOW}]}]
        elif path in ["/sync", "/bootstrap"]:
            for key, values in body.get("upserts", {}).items():
                if isinstance(values, list):
                    existing = {item["id"]: item for item in state.get(key, [])}
                    existing.update({item["id"]: item for item in values})
                    state[key] = list(existing.values())
            data = {"user": {"id": "local-test", "is_guest": False}, "state": {
                key: value for key, value in state.items() if key not in ["plans", "jobs"]}}
        elif path.startswith("/tasks/") and path.endswith("/plans"):
            task_id = path.split("/")[2]
            if self.command == "POST":
                data = dict(body, id="plan-" + task_id, task_id=task_id, revision=1, created_at=NOW, updated_at=NOW)
                state["plans"][data["id"]] = data
                status = 201
            else:
                data = [p for p in state["plans"].values() if p["task_id"] == task_id]
        elif path == "/remote-jobs":
            assert body.get("plan_id") in state["plans"], body
            task = next(t for t in state["tasks"] if t["id"] == body["task_id"])
            assert task["executor_type"] in ["ai", "collaboration"], task
            assert body.get("expected_task_revision", 0) > 0, body
            data = dict(body, id="job-ui", status="queued", revision=1, created_at=NOW, updated_at=NOW)
            state["jobs"]["job-ui"] = data
            state["dispatch_time"] = time.monotonic()
            state["plans"][body["plan_id"]].update(status="queued", revision=2)
        elif path == "/remote-jobs/job-ui":
            data = state["jobs"]["job-ui"]
            if data["status"] not in ["completed", "cancelled"]:
                status_name = "running" if time.monotonic() - state["dispatch_time"] < 5 else "awaiting_review"
                data.update(status=status_name, result_summary="本地测试执行完成", revision=3)
                plan = state["plans"][data["plan_id"]]
                plan.update(status=status_name, revision=max(plan["revision"], 3))
        elif path.startswith("/plans/") and path.endswith("/accept"):
            data = state["plans"][path.split("/")[2]]
            assert body.get("evidence_ids") == ["job-ui"], body
            assert body.get("expected_revision") == data["revision"], body
            assert len(body.get("criteria", [])) == len(data["criteria"]), body
            if scenario.startswith("conflict"):
                data.update(criteria=["新增验收项"], revision=data["revision"] + 1)
                status, code = 409, 40901
            else:
                data.update(status="accepted", revision=data["revision"] + 1)
                state["jobs"]["job-ui"]["status"] = "completed"
        elif path.startswith("/plans/") and path.endswith("/cancel"):
            data = state["plans"][path.split("/")[2]]
            assert body.get("expected_revision") == data["revision"], body
            data.update(status="cancelled", revision=data["revision"] + 1)
            state["jobs"]["job-ui"]["status"] = "cancelled"
        else:
            status, code = 404, 40400
        # Never include private fixture bookkeeping in Bootstrap.
        if path in ["/sync", "/bootstrap"]:
            data["state"].pop("dispatch_time", None)
        payload = json.dumps({"code": code, "message": "local fixture", "data": data}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18768), Handler).serve_forever()
