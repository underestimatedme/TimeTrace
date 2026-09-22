# Real Valley + Python Runner cancellation regression

`valley_runner_test.go` is a test overlay for Valley's existing `timetrace`
package. It uses its real fixture/migration/auth helpers, starts the production
HTTP router on loopback, and invokes `runner_cancellation.py`. The Python
scenario uses the real Agent, CloudClient and SQLite Database; only the external
AI adapter is fake. Owner cancellation, runner renewals and event batches all
go through real HTTP into PostgreSQL.

Two scenarios assert terminal cancelled, original sequence/observed_at values,
an empty recovered outbox and successful execution of the next claimed job:
normal delivery and a lost response **after** Valley committed the batch.
The latter closes/reopens the real SQLite database before whole-batch retry.

Start an isolated PostgreSQL instance on **127.0.0.1:54329** and use an independent
UTF8 test database. Never point these tests at production. The test rejects any
DSN without the explicit local host and port, and fails (not skips) if the Python
scenario path is missing. Example for this workspace:

```sh
# First ensure the overlay destination does not already exist; do not overwrite
# another task's file. Copy only this test, never change Valley production code.
cp /opt/coding/planb/github/.worktrees/timetrace-workspace-review/cli/tests/integration/valley_runner_test.go /opt/coding/planb/github/Valley/internal/apps/timetrace/f09_cross_runner_integration_test.go
cd /opt/coding/planb/github/Valley
LC_ALL=C APP_DSN_TIMETRACE_TEST='host=127.0.0.1 port=54329 user=postgres dbname=valley_f09_final_test sslmode=disable' F09_RUNNER_SCENARIO='/opt/coding/planb/github/.worktrees/timetrace-workspace-review/cli/tests/integration/runner_cancellation.py' go test ./internal/apps/timetrace -run TestF09PythonRunnerCancellationBatch -count=1 -v
```

Set `F09_PYTHON=python3.12` to test that interpreter. For the complete TimeTrace
backend suite use the same environment with `go test ./internal/apps/timetrace/...
-count=1 -json`. Keep the environment set while the overlay is installed. Remove
only the temporary `f09_cross_runner_integration_test.go` copy after testing; the
source remains here. No Valley commit, production deployment, lease bypass or
server protocol change is required.
