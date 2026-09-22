#!/bin/sh
# Provisioning only: workflow setup/assertions live in the Python/Go suite.
set -eu
: "${VALLEY_ROOT:?Set VALLEY_ROOT to the paired Valley checkout}"
TIMETRACE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export TIMETRACE_ROOT
KEJI_CLI_ROOT="$TIMETRACE_ROOT/cli"
export KEJI_CLI_ROOT
if pg_isready -h 127.0.0.1 -p 54329 >/dev/null 2>&1; then
    echo 'Port 54329 is already occupied; use the documented existing-isolated-server command.' >&2
    exit 1
fi
F12_PG_DIR=$(mktemp -d /tmp/keji-workspace-postgres.XXXXXX)
cleanup() {
    pg_ctl -D "$F12_PG_DIR/data" -m fast stop >/dev/null 2>&1 || true
    echo "Isolated PostgreSQL stopped; diagnostic files retained at $F12_PG_DIR"
}
trap cleanup EXIT HUP INT TERM
initdb -D "$F12_PG_DIR/data" -A trust -U postgres --encoding=UTF8 --locale=C > "$F12_PG_DIR/init.log"
pg_ctl -D "$F12_PG_DIR/data" -l "$F12_PG_DIR/server.log" -o '-h 127.0.0.1 -p 54329' start
export APP_DSN_TIMETRACE_TEST='host=127.0.0.1 port=54329 user=postgres dbname=valley_timetrace_test sslmode=disable client_encoding=UTF8'
export LC_ALL=C
cd "$VALLEY_ROOT"
if [ "$#" -eq 0 ]; then set -- -run TestWorkspacePythonIntegration; fi
go test -race -v ./internal/apps/timetrace/ -count=1 "$@"
