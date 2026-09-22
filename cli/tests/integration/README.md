# Cross-repository integration

The F09 temporary Go overlay has been replaced by the permanent Valley test
`TestWorkspacePythonIntegration` and the TimeTrace suite in
[`tests/integration`](../../../tests/integration/README.md).

No copied or uncommitted overlay is required. The permanent suite covers the
original cancellation/lost-response cases, creates users/runners/tasks through
the production HTTP API, and independently compares SQLite events with actual
PostgreSQL records.
