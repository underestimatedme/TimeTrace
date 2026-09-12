# KeJi Remote Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in KeJi user bind a Mac, register local repositories, and dispatch Claude Code or Codex work from an iPhone through Valley with reliable status and result reporting.

**Architecture:** Valley owns device authorization, runner credentials, remote job state, leases, commands, and event history in PostgreSQL. The local `keji agent` maintains outbound HTTPS control traffic, persists claims and event outbox in SQLite, and runs the existing provider adapters inside registered worktrees. iOS consumes user APIs and treats remote execution state as server authoritative.

**Tech Stack:** Go/Gin/GORM/PostgreSQL in Valley; Python 3.9 standard library CLI; SwiftUI/Swift concurrency iOS 17+; React/Vite/Vitest for the prototype.

**Spec:** `docs/superpowers/specs/2026-09-12-keji-remote-runner-feasibility.md`

## Global Constraints

- Product API remains `/timetrace/api/v1` with the established response envelope and opaque TimeTrace tokens.
- Provider credentials and raw source/log output remain on the computer.
- Remote mode accepts only locally registered repositories and cannot increase local permissions.
- Durable state, leases, idempotency, and ownership are enforced in PostgreSQL; Redis wakeups are optional.
- Remote execution fields are server authoritative and cannot be overwritten by legacy sync.
- Each runner executes at most one remote job at a time in the first release.
- Valley's existing dirty checkout is never modified; backend work runs in an isolated worktree.
- New behavior follows red-green-refactor and each slice receives fresh tests before commit.

---

### Task 1: Finish and checkpoint the existing frontend QA work

**Files:**
- Modify: `design/src/pages/Focus.tsx`
- Modify: `design/src/pages/Timeline.tsx`
- Modify: `design/src/pages/Today.tsx`
- Create: `design/src/lib/time.ts`
- Create: `design/src/lib/time.test.ts`
- Modify: `design/package.json`
- Include the existing iOS QA files already present in the checkout.

**Interfaces:**
- Produces `useNow(intervalMs?: number): number`, which updates time from an effect rather than calling `Date.now()` during render.
- Produces a reproducible React lint/test/build command and a clean checkpoint for later remote work.

- [ ] Add Vitest and a failing behavior test proving elapsed time is derived from an injected timestamp without an impure render call.
- [ ] Run the focused test and lint; record the expected failure from the missing helper/current `Date.now()` calls.
- [ ] Implement the time hook/helper and replace all four render-time calls.
- [ ] Run React tests, lint, and build; run `ios/scripts/run-qa.sh` and inspect its summary.
- [ ] Commit the existing iOS QA changes, tracked React prototype, feasibility spec, and this plan in coherent commits; push `feature/ios-app` as previously requested.

### Task 2: Add Valley runner identity and device authorization

**Files:**
- Create/modify in the isolated Valley worktree: `internal/apps/timetrace/remote_model.go`
- Create: `internal/apps/timetrace/remote_auth.go`
- Modify: `internal/apps/timetrace/app.go`
- Modify: `internal/apps/timetrace/repository.go`
- Create: `internal/apps/timetrace/remote_auth_test.go`
- Modify: `internal/apps/timetrace/app_integration_test.go`

**Interfaces:**
- Produces device authorization create/poll/inspect/approve/activate endpoints from the design.
- Produces runner-only access/refresh tokens with a distinct audience and server-side revocation check.
- Stores only device-code digests, keyed short-code digests, and refresh-token digests.

- [ ] Write repository and HTTP tests for expiry, wrong code, brute-force limiting, cross-user inspection, duplicate approval, activation idempotency, refresh rotation, reuse revocation, and runner revocation.
- [ ] Run focused Go tests and verify the new tests fail because the models/routes do not exist.
- [ ] Add migrations, service/repository rules, handlers, and typed error mapping.
- [ ] Run focused tests, `go test -race ./internal/apps/timetrace`, and `go test ./...`.
- [ ] Commit the runner identity slice on `codex/timetrace-remote-runner`.

### Task 3: Add Valley workspaces, jobs, leases, commands, and events

**Files:**
- Create: `internal/apps/timetrace/remote_job.go`
- Create: `internal/apps/timetrace/remote_job_test.go`
- Modify: `internal/apps/timetrace/remote_model.go`
- Modify: `internal/apps/timetrace/app.go`
- Modify: `internal/apps/timetrace/sync.go`
- Modify: `internal/apps/timetrace/app_integration_test.go`

**Interfaces:**
- Produces runner inventory and user list/create/read/control endpoints.
- Produces atomic `ClaimJob`, `RenewLease`, `AppendEvents`, `AckCommand`, and `ReconcileAttempt` operations guarded by attempt ID, lease epoch, revision, and ownership.
- Encrypts remote prompt fields with versioned AEAD configuration and rejects production startup without a valid key when the feature is enabled.

- [ ] Write failing tests for ownership, idempotency-key replay/mismatch, concurrent claim, stale epoch writes, command revisions, event replay, expiration, and old sync attempts to overwrite a linked remote execution.
- [ ] Run focused tests and retain the expected red results.
- [ ] Implement schema, state transitions, transaction guards, request bounds, encryption, cleanup policy, and routes.
- [ ] Run focused concurrency tests, all TimeTrace backend tests, and full Valley tests.
- [ ] Commit the remote job slice.

### Task 4: Turn the CLI into a persistent outbound runner

**Files:**
- Create: `cli/keji/cloud.py`
- Create: `cli/keji/credentials.py`
- Create: `cli/keji/agent.py`
- Create: `cli/keji/process.py`
- Modify: `cli/keji/db.py`
- Modify: `cli/keji/config.py`
- Modify: `cli/keji/cli.py`
- Modify: `cli/keji/scheduler.py`
- Modify: `cli/keji/adapters/base.py`
- Modify: `cli/launchd/com.keji.run.plist`
- Create: `cli/tests/test_cloud.py`
- Create: `cli/tests/test_agent.py`
- Create: `cli/tests/test_process.py`

**Interfaces:**
- Produces `keji cloud login|status|logout`, `keji workspace add|list|remove`, and `keji agent run|install|doctor`.
- Persists runner/workspace/job mappings and an ACKed event outbox in SQLite.
- Runs stdout/stderr concurrently with an end-to-end timeout and process-group cancellation while keeping heartbeats independent.

- [ ] Write failing tests for device polling, token refresh serialization, Keychain command boundaries, workspace canonicalization, unknown repository rejection, claim persistence before process start, duplicate claim recovery, ordered event replay, cancellation acknowledgement, and stderr backpressure/timeout.
- [ ] Run the focused CLI tests and verify failures are for missing behavior.
- [ ] Implement the HTTP client, macOS Keychain adapter, schema migration, agent loop, process manager, launchd installation rendering, and local execution lock.
- [ ] Run all 3 provider/agent fixture suites and the full CLI test suite.
- [ ] Commit the CLI runner slice on a TimeTrace feature branch.

### Task 5: Replace simulated iOS execution with the remote workflow

**Files:**
- Create: `ios/KeJi/Models/RemoteExecutionModels.swift`
- Create: `ios/KeJi/Networking/RemoteExecutionClient.swift`
- Create: `ios/KeJi/Features/AITools/RunnerListView.swift`
- Create: `ios/KeJi/Features/AITools/RunnerPairingView.swift`
- Modify: `ios/KeJi/Features/AITools/AIToolsView.swift`
- Modify: `ios/KeJi/Features/Tasks/TaskCreateView.swift`
- Modify: `ios/KeJi/Features/AIExecution/AIExecutionView.swift`
- Modify: `ios/KeJi/Store/AppStore+AI.swift`
- Modify: `ios/KeJi/Networking/SyncEngine.swift`
- Create/modify tests under `ios/KeJiTests` and `ios/KeJiUITests`.

**Interfaces:**
- Produces signed-in pairing, runner/workspace/tool selection, idempotent dispatch, event cursor polling, cancel/interrupt/continue, and awaiting-review state.
- Preserves simulator/demo mode behind an explicit launch option; production remote tasks never tick fabricated usage.

- [ ] Write failing decoding/client/store tests for pairing states, dispatch retry, cursor replay, expired auth, server-authoritative merge, offline pending submission, cancellation pending acknowledgement, and unknown usage values.
- [ ] Run focused XCTest targets and verify expected failures.
- [ ] Implement models, endpoints, views, store transitions, polling cancellation, foreground refresh, and accessibility identifiers.
- [ ] Extend UI tests for pairing, dispatch, progress, offline/error, cancel acknowledgement, and review.
- [ ] Generate the Xcode project, run all unit/UI tests, and inspect simulator screens.
- [ ] Commit the iOS remote slice.

### Task 6: Validate real Claude/Codex execution and recovery

**Files:**
- Modify adapters and tests only when a probe demonstrates a concrete incompatibility.
- Update: `cli/探针验证记录-2026-09-02.md`
- Create: `docs/remote-runner-operations.md`

**Interfaces:**
- Produces a versioned capability report for installed Claude/Codex and operational guidance for authentication, LaunchAgent, sleep, revocation, and data retention.

- [ ] Run no-cost/version probes and a throwaway-repository start/resume/cancel scenario for both installed tools using the configured user accounts.
- [ ] For every observed mismatch, add a failing fixture or process test before changing adapter behavior.
- [ ] Run a local Valley-to-agent integration with injected network loss, duplicate delivery, runner restart, and stale lease.
- [ ] Run at least a bounded soak during this task; document the duration and leave the 24-hour production gate explicit if the session cannot supply it.
- [ ] Commit probe evidence and fixes.

### Task 7: Integrate, migrate, deploy safely, and verify the original four outcomes

**Files:**
- Modify Valley deployment configuration and safe `.env.example` entries.
- Modify: `.github/workflows/ios.yml`
- Modify: `ios/README.md`
- Modify: `cli/README.md`
- Modify: `design/README.md`
- Create: `docs/remote-runner-release-checklist.md`

**Interfaces:**
- Produces a feature-flagged rollout path that keeps cancellation/result reporting active during rollback.

- [ ] Verify an empty and populated database migration, encryption-key validation, ownership/security tests, redacted logs, and rollback behavior.
- [ ] Verify React tests/lint/build, CLI tests, Go tests/race tests, and iOS unit/UI tests from fresh commands.
- [ ] Deploy Valley only after tests pass, smoke its health and new API against production without exposing secrets, then run the true iPhone-on-cellular acceptance flow when a physical device is available.
- [ ] Push TimeTrace and Valley branches and report exact commits, checks, external configuration, and any unverified physical-device/24-hour gates.
