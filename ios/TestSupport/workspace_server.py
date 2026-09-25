"""Local HTTP contract fixture: python3 TestSupport/workspace_server.py.

No production credentials or services. UI actions use the production HTTP stack.
"""
import json
import re
import time
from urllib.parse import urlsplit, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NOW = "2026-09-15T10:00:00Z"
USAGE_EVENT_NAMES = {"screen_view", "dispatch_started", "dispatch_succeeded", "dispatch_failed", "schedule_created",
                     "pairing_step", "plan_accepted", "report_opened", "report_action", "quota_viewed", "app_open"}
states = {}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def do_PUT(self):
        self.handle_request()

    def do_PATCH(self):
        self.handle_request()

    def handle_request(self):
        parts = self.path.strip("/").split("/")
        scenario, path = parts[0], "/" + "/".join(parts[1:])
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or "{}")
        state = states.setdefault(scenario, {"tasks": [], "projects": [], "goals": [], "plans": {}, "jobs": {}})
        data, status, code = {}, 200, 0
        if path == "/auth/guest" or path == "/auth/refresh":
            data = {"access_token": "local-test", "refresh_token": "local-refresh", "expires_in": 900}
        elif path == "/feedback":
            assert {"body", "idempotency_key"} <= set(body) <= {"body", "idempotency_key", "include_diagnostics"}, body
            assert self.headers.get("Authorization") == "Bearer local-test"
            if scenario.startswith("feedback-ok"):
                # 与 Valley 一致：同一幂等键返回同一张单（200），新键建新单（201）。
                tickets = state.setdefault("feedback_tickets", {})
                key = body["idempotency_key"]
                if key in tickets:
                    data = tickets[key]
                else:
                    data = {"ticket_id": "fb-ui-%d" % (len(tickets) + 1), "body": body["body"],
                            "status": "received", "include_diagnostics": body.get("include_diagnostics", False),
                            "created_at": NOW, "updated_at": NOW}
                    tickets[key] = data
                    status = 201
            else:
                previous = state.get("feedback")
                if previous is None:
                    # The server accepted the ticket but the first response failed.
                    state["feedback"] = body
                    status, code = 503, 50300
                elif previous != body:
                    status, code = 409, 40900
                else:
                    data = {"ticket_id": "ticket-f11", "body": body["body"], "status": "received"}
        elif path.startswith("/reports"):
            facts = [
                {"id": "h1", "task_id": "t", "track": "human", "state": "known", "start": "2026-09-14T20:00:00Z", "end": "2026-09-14T20:10:00Z"},
                {"id": "h2", "task_id": "t", "track": "human", "state": "known", "start": "2026-09-14T20:05:00Z", "end": "2026-09-14T20:10:00Z"},
                {"id": "a1", "task_id": "t", "track": "ai", "state": "known", "start": "2026-09-14T20:00:00Z", "end": "2026-09-14T20:10:00Z"},
                {"id": "a2", "task_id": "t", "track": "ai", "state": "known", "start": "2026-09-14T20:00:00Z", "end": "2026-09-14T20:10:00Z"}]
            query = parse_qs(urlsplit(path).query)
            # Like Valley, answer in the zone the client asked for; the app rejects any
            # other zone, and CI machines are not in the developer's time zone.
            zone = (query.get("zone", [""])[0] if self.command == "GET" else body.get("zone")) or "Asia/Dubai"
            data = {"local_date": query.get("date", [""])[0] if self.command == "GET" else body["date"],
                    "revision": 8 if self.command == "POST" else 7, "status": "draft", "coverage": 0.79,
                    "total_score": 95, "human_seconds": 600, "ai_seconds": 1200, "waiting_seconds": None,
                    "evidence_ids": ["a1", "a2"], "baseline_version": "phase-facts-v2",
                    "breakdown": {"zone": zone, "evidence_coverage": 1, "facts": facts}}
            if scenario.startswith("reports-project"):
                for fact in facts:
                    fact["task_id"] = "quota"
                facts.append(dict(facts[-1], id="other-project", task_id="outside"))
                data["ai_seconds"] = 1800
            if scenario.startswith("reports-zone-mismatch"):
                data["breakdown"]["zone"] = "America/New_York" if zone != "America/New_York" else "Asia/Dubai"
        elif path == "/preferences":
            # 与 Valley PutPreferences 一致：乐观锁，版本不符返回 409/40901 与当前记录。
            current = state.setdefault("preferences", {"revision": 0, "data": {}, "updated_at": NOW})
            if self.command == "GET":
                data = current
            elif body.get("expected_revision") != current["revision"]:
                data, status, code = current, 409, 40901
            else:
                current = {"revision": current["revision"] + 1, "data": body.get("data", {}), "updated_at": NOW}
                state["preferences"] = current
                data = current
        elif path.split("?")[0] == "/reset-signals":
            # 与 Valley 的 cached 形状一致：来源链接 + 公共重置日历事件（新的在前）。
            # 事件落在所请求月份的 10 日 / 14 日（from 是本地月初前一天）；不带 from 时用当前 UTC 月。
            query = parse_qs(urlsplit(path).query)
            start = query.get("from", [""])[0]
            if start:
                month = time.strftime("%Y-%m", time.gmtime(time.mktime(time.strptime(start, "%Y-%m-%d")) + 2 * 86400))
            else:
                month = time.strftime("%Y-%m", time.gmtime())
            data = {"integration_status": "cached",
                    "sources": [{"name": "BetterOPC", "url": "https://betteropc.com"}],
                    "signals": [], "cache_age_seconds": 0,
                    "note": "公共信号来自 BetterOPC 的公开动态，仅供参考。公共信号不替代个人额度核验。",
                    "events": [
                        {"id": "rse_fixture_announce", "product": "codex", "provider": "codex", "kind": "announcement",
                         "occurred_at": month + "-14T09:00:00Z", "text": "Codex 将发放重置卡",
                         "source_url": "https://x.com/betteropc/status/3", "status": "scheduled", "label": "发重置卡",
                         "confidence": "possible"},
                        {"id": "rse_fixture_claude", "product": "claude-code", "provider": "claude", "kind": "confirmed_reset",
                         "occurred_at": month + "-10T13:30:00Z", "text": "Claude Code 用量已重置",
                         "source_url": "https://x.com/betteropc/status/2", "status": "executed", "label": "",
                         "confidence": "confirmed"},
                        {"id": "rse_fixture_codex", "product": "codex", "provider": "codex", "kind": "confirmed_reset",
                         "occurred_at": month + "-10T12:00:00Z", "text": "Codex 用量已重置",
                         "source_url": "https://x.com/betteropc/status/1", "status": "executed", "label": "",
                         "confidence": "confirmed"}]}
        elif path == "/quota":
            data = {"pools": [{"pool_id": "pool-codex", "provider": "codex", "availability": "available",
                               "windows": [{"pool_id": "pool-codex", "scope": "short", "kind": "codex",
                                            "limit_id": "", "window_mins": 300, "used_percent": 38,
                                            "observed_at": NOW, "expires_at": "2099-01-01T00:00:00Z",
                                            "source": "runner", "confidence": "exact"}]}],
                    "observed_at": NOW}
            if scenario.startswith("report-schedule"):
                # 报告页的「安排在重置后执行」需要一个真实的未来重置时刻（相对设备当前时间）。
                reset = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3 * 3600))
                data["pools"][0]["windows"][0]["reset_at"] = reset
        elif path == "/events":
            # 与 Valley usage_events.go 相同的闭合字典：任何不合规的批次整批 422。
            log = state.setdefault("usage_events", {"events": [], "invalid": 0})
            if self.command == "GET":
                data = log
            else:
                assert self.headers.get("Authorization") == "Bearer local-test"
                events = body.get("events") or []
                valid = 0 < len(events) <= 100 and len(body.get("app_version", "")) <= 32
                for event in events:
                    props = event.get("props") or {}
                    valid = valid and event.get("name") in USAGE_EVENT_NAMES and len(props) <= 8 and all(
                        re.fullmatch(r"[a-z_]{1,32}", key) and isinstance(value, (str, int, float, bool))
                        and (not isinstance(value, str) or len(value) <= 64) for key, value in props.items())
                if valid:
                    log["events"].extend(events)
                    data = {"accepted": len(events), "dropped": 0}
                else:
                    log["invalid"] += 1
                    status, code = 422, 42230
        elif path == "/device-authorizations/inspect":
            # keji://pair 链接里的小写码必须在手机上规范成大写再发出。
            assert body.get("user_code") == "ABCD1234", body
            data = {"device_name": "Fixture Mac", "platform": "darwin", "client_version": "0.4.0",
                    "requested_at": NOW, "expires_at": "2099-01-01T00:00:00Z", "permissions": ["receive_jobs"]}
        elif path == "/device-authorizations/approve":
            assert body.get("user_code") == "ABCD1234", body
            data = {"approved": True}
        elif path == "/runners/runner-ui" and self.command == "PATCH":
            name = (body.get("name") or "").strip()
            assert 1 <= len(name) <= 80, body
            state["runner_name"] = name
            data = {"id": "runner-ui", "name": name, "platform": "darwin", "client_version": "1",
                    "status": "online", "created_at": NOW, "updated_at": NOW}
        elif path == "/runners":
            data = [{"runner": {"id": "runner-ui", "name": state.get("runner_name", "Test Mac"), "platform": "darwin", "client_version": "1",
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
            user_id = scenario if scenario.startswith("feedback-") else "local-test"
            data = {"user": {"id": user_id, "is_guest": False}, "state": {
                key: value for key, value in state.items() if key not in ["plans", "jobs", "feedback", "feedback_tickets", "preferences", "runner_name", "usage_events"]}}
        elif path.startswith("/tasks/") and path.endswith("/plans"):
            task_id = path.split("/")[2]
            if self.command == "POST":
                data = dict(body, id="plan-" + task_id, task_id=task_id, revision=1, created_at=NOW, updated_at=NOW)
                if scenario.startswith("happy"):
                    data["criteria"] = ["行为符合要求", "结果经人工检查"]
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
            if body.get("not_before"):
                data["not_before"] = body["not_before"]   # echoed back like Valley does
            state["jobs"]["job-ui"] = data
            state["dispatch_time"] = time.monotonic()
            state["plans"][body["plan_id"]].update(status="queued", revision=2)
        elif path == "/remote-jobs/job-ui":
            data = state["jobs"]["job-ui"]
            elapsed = time.monotonic() - state["dispatch_time"]
            if data["status"] not in ["completed", "cancelled"]:
                if data.get("not_before") and elapsed < 4:
                    pass   # scheduled: stays queued with not_before until "due"
                else:
                    status_name = "running" if elapsed < 5 else "awaiting_review"
                    data.update(status=status_name, result_summary="本地测试执行完成", revision=3)
                    if status_name == "awaiting_review":
                        data["output_tail"] = "$ pytest\n3 passed\n"
                    plan = state["plans"][data["plan_id"]]
                    plan.update(status=status_name, revision=max(plan["revision"], 3))
        elif path.startswith("/plans/") and path.endswith("/accept"):
            data = state["plans"][path.split("/")[2]]
            assert body.get("evidence_ids") == ["job-ui"], body
            assert body.get("expected_revision") == data["revision"], body
            assert len(body.get("criteria", [])) == len(data["criteria"]), body
            assert body.get("criteria", []) == [{"index": i, "accepted": True} for i in range(len(data["criteria"]))], "criterion selections missing"
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
