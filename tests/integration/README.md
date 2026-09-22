# Workspace integration regression

Run from committed paired checkouts; no overlay is copied. Requires Go, Git,
PostgreSQL (`initdb`, `pg_ctl`, `pg_isready`) on PATH and Python 3.9 or 3.12.

```sh
VALLEY_ROOT=/path/to/Valley KEJI_PYTHON=/usr/bin/python3 sh tests/integration/run.sh
VALLEY_ROOT=/path/to/Valley KEJI_PYTHON=/opt/homebrew/bin/python3.12 sh tests/integration/run.sh
```

The runner provisions a fresh UTF8 cluster in a unique temporary directory,
listens only on `127.0.0.1:54329`, and stops its own server on exit. It refuses
an occupied port and retains its diagnostic files. It never stops another
PostgreSQL instance. No subscription CLI is invoked. The test database is
created/migrated by Valley's test fixture; users, pairing, inventory, tasks,
Plans, dispatch, quota samples, claims, renewals, cancellation, events,
acceptance and reports go through production registered HTTP routes.
Authentication uses Valley's supported local-mode OTP and real `sms.LogSender`
with a disabled logger; no test SMS implementation or external delivery is used.
This verifies auth/token/database behavior, not production SMS delivery.

For an **already-owned isolated** server, the test is normally discovered by
Go's full timetrace suite. With `KEJI_WORKSPACE_INTEGRATION_REQUIRED=1` (set by
`run.sh`) database failures or missing paired tests fail; do not accept any SKIP
in that mode. Without the variable — the shared Valley pipeline, a plain
`go test ./...` — the Go test skips, because no isolated cluster exists there:

```sh
cd /path/to/Valley
LC_ALL=C APP_DSN_TIMETRACE_TEST='host=127.0.0.1 port=54329 user=postgres dbname=valley_timetrace_test sslmode=disable client_encoding=UTF8' \
  TIMETRACE_ROOT=/path/to/TimeTrace KEJI_PYTHON=/usr/bin/python3 \
  go test -race -json ./internal/apps/timetrace/ -count=1
```

`TestWorkspacePythonIntegration` invokes the unittest class in
`test_workspace_flow.py` against the real router and PostgreSQL. Python uses
the production Agent, CloudClient, real Git worktrees and durable SQLite.
Only `ExternalAI` simulates an external AI provider. `FaultTransport` interrupts
urlopen before sending, or discards the actual response after PostgreSQL has
committed; it never manufactures an HTTP response. Go independently compares
each reported SQLite event's attempt, sequence, type and observation timestamp
with PostgreSQL and rejects duplicate/missing records.

Scenarios: full quota/checkpoint/original-native-session resume and human
criterion/evidence acceptance followed by a 90%-covered, 100-point private
report; cancellation with stale event rejection; disconnected outbox recovery
after SQLite restart; committed-response-loss replay; absent/false billing
capability; concurrent same-runner claims and a second runner's denied access.
The full-flow scenario explicitly proves an exhausted weekly window remains
blocked after the short window recovers. Report money remains unknown.

Logs contain the two checked-out SHAs, test counts, SKIP count, job/attempt/
lease/provider-session/event IDs and observation times. Never add request
bodies, credentials, token values, provider output, or SQL bind parameters.

Other matrix commands (from the respective directories):

```sh
# cli
DEVELOPER_DIR=/Library/Developer/CommandLineTools /usr/bin/python3 -m unittest discover -s tests
DEVELOPER_DIR=/Library/Developer/CommandLineTools /opt/homebrew/bin/python3.12 -m unittest discover -s tests
# ios: start this separate contract fixture in another terminal
/usr/bin/python3 TestSupport/workspace_server.py
xcodegen generate
xcodebuild test -project KeJi.xcodeproj -scheme KeJi -destination 'platform=iOS Simulator,id=DEDICATED_DEVICE_ID' -only-testing:KeJiTests
xcodebuild test -project KeJi.xcodeproj -scheme KeJi -destination 'platform=iOS Simulator,id=DEDICATED_DEVICE_ID' -only-testing:KeJiUITests/WorkspaceFlowTests
```

The iOS HTTP fixture verifies UI serialization/selection and is **not** the
real backend E2E evidence. Select an existing dedicated KeJi device or create
one; never shut down all simulators. Preserve the first log before retrying
simulator preflight failures. An application assertion failure is not a flake.

All real adapters keep `can_enforce_zero_spend=false`. Real Claude/Codex
subscription billing guarantees, native-session persistence and exact account
pool binding remain manual release gates. The fake adapter proves orchestration
only; it does not authorize unattended production execution. No push, merge,
production migration, deployment or App Store action is part of this suite.

The original 21-issue evidence matrix is in [review-evidence.md](review-evidence.md).
