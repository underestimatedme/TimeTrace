# Original review: 21-issue evidence index

Original: `keji-ai-workspace-review-2026-09-15.md`. V commits are in Valley;
T commits are in TimeTrace. These are actual regression names, not invented
coverage labels. Run the full commands in [README.md](README.md); F12 adds the
common real HTTP/Python/PostgreSQL acceptance harness. Earlier fixes are retained.

| Issue | Fix commit(s) | Executable evidence | What it proves |
|---|---|---|---|
| V-01 cancelled Plan revived | V `53f2255` | `TestWorkspaceCancellationSurvivesDelayedEvents`; F12 `test_cancel_rejects_old_events` | Late events cannot undo owner cancellation; next claim stays fenced. |
| V-02 DAG missing from execution gate | V `53f2255` | `TestWorkspaceDependencyCheckedAtCreateAndClaim`, `TestWorkspaceClaimUsesAuthoritativePlanStatus` | Both dispatch and transactional claim recheck actual Plan dependencies/status. |
| V-03 provider inferred from profile name | V `eb0fd44`; T `7140adf` | `TestQuotaIdentityCustomProfileUsesRegisteredProvider`; `test_explicit_provider_dispatches_custom_profile_and_missing_provider_blocks` | A custom profile cannot escape its registered provider's quota. |
| V-04 split/bypassed acceptance | V `cefcfe1`, `ace113e` | `TestReviewLegacyCompleteCannotBypassCriteria`, `TestPlanAcceptanceCompletesJobAndAggregatesTask`, `TestPlanReviewCancellationPreservesFinishedExecution`; F12 full-flow test | Explicit criterion/evidence acceptance atomically closes job/Plan and aggregates Task; cancellation preserves execution facts. |
| V-05 legacy sync overwrites facts | V `0aa8d4f` | `TestLegacySyncPreservesRemoteExecutionFacts`, `TestLegacySyncPreservesPlanProjectionsAndAllowsEdits` | Newer/repeated offline payloads cannot change runtime facts or task/goal project ownership; legal description edits survive. |
| V-06 idempotency omits PlanID | V `53f2255` | `TestWorkspaceIdempotencyIncludesNormalizedPlan`, `TestWorkspaceIdempotencyPreservesExistingJobRetries` | Same target retries replay; changing normalized Plan conflicts. |
| V-07 probe limited per job | V `eb0fd44` | `TestQuotaIdentityProbeReservedAcrossJobsAndRunners`, `TestQuotaIdentityProbeRollsBackWithClaim` | One shared pool/window reservation across jobs/runners, atomic with claim. |
| V-08 migration inserts extra default Plan | V `d19a3e7`, `229be45` | `TestMigratePlansLeavesCustomOnlyTaskUnchanged`, `TestMigratePlansWaitsForCustomPlanCommit`, `TestMigratePlansExcludesOwnersOutsideFenceSnapshot` | Repeated and concurrent migration preserves custom scope and fences applicable owners. |
| V-09 wrong report phases/day | V `95bd8d8`, `feac72f`, `9073b12`, `469bf03`; T `975ea5a`, `11fa97c` | `TestReportRealEventsCrossMidnightAndParallel`, `TestReportOccurrenceLateBatchAndLegacyUnknown`, `TestReportConfirmedScopeScoringUsesAcceptanceEvidence`; F12 full-flow/lost-response tests | Observed immutable phases, not upload time; separate human/AI/waiting; attempts do not duplicate accepted delivery. |
| V-10 report/preference concurrency 500 | V `95bd8d8`, `212ae62` | `TestReportConcurrentRevisions`, `TestPreferencesConcurrentFirstWrite`, `TestPreferencesHTTPConflictCarriesCurrent` | Concurrent report revisions stay unique; first preference write returns one success/one 409 with current revision. |
| V-11 recommendations bypass reality/constants | V `8ceab5a`, `a40658c`; T `2845cbd` | `TestRecommendationExecutionGates`, `TestRecommendationDoesNotAuthorizeLaterClaim`, `TestRecommendationScoresRealGoalAndDownstreamUnlock`, `TestRecommendationRunnerLiveness` | Shared read-only eligibility, real score inputs and expiring runner liveness; recommendation grants no execution authority. |
| V-12 guest merge loses domains | V `d19a3e7`, `229be45` | `TestGuestMergePreservesMigratedGraphAndRetry`, `TestGuestMergeConflictHistoryAndFeedbackReplay`, `TestGuestMergeRollsBackEveryDomainOnFailure`, `TestGuestMergeRejectsEveryStaleRunnerGraphMutation` | Graph/history/ownership preserved or fully rolled back; stale source runner cannot mutate destination. |
| T-01 scheduler skips zero-spend gate | T `c0dfe3a`, `12d8a3d`, `85718a1` | `test_missing_or_false_zero_spend_capability_blocks_start_and_resume`, `test_malformed_capabilities_block_without_execution`, `test_raising_capabilities_property_blocks_without_execution` | Missing/false/malformed/throwing capability fails closed at execution entry points. |
| T-02 Python 3.9 imports fail | T `c0dfe3a` | Full 3.9 and 3.12 discovery; `test_adapters_are_management_only`, `test_management_only_adapters_do_not_execute` | All adapters import on both declared interpreters; management adapters never execute. F12 also adds `test_go_rfc3339_lease_fraction_is_valid_on_python39`. |
| T-03 quota limit identity lost | T `7140adf`; V `eb0fd44` | `test_colliding_primary_limits_preserve_identity`, `test_sample_dedup_identity_includes_pool_profile_and_window_duration`, `TestQuotaIdentityCollidingPayloadHTTPClaim` | Total/model/window identities remain independent through payload and real ingest/claim. F12 full flow proves weekly exhaustion survives short-window recovery. |
| T-04 preparation crosses lease | T `50ebf7e`, `65ae3b9`, `616d142` | `test_preparation_crossing_lease_deadline_never_spawns`, `test_resume_preparation_crossing_deadline_never_spawns`, `test_executor_delay_cannot_start_after_lease_deadline`, `test_hung_renewal_cannot_extend_writer_past_deadline` | Rechecks at actual start/resume boundary; expired or failed renewals never grant process authority. |
| T-05 unsafe checkpoint fallback/session | T `50ebf7e`, `65ae3b9`, `616d142` | `test_invalid_checkpoint_never_falls_back_to_start`, `test_checkpoint_records_actual_worktree_state_and_output`, `test_crashed_owner_with_live_orphan_keeps_fence`; F12 full-flow test | Native session, worktree and output evidence are validated; corrupt/missing evidence blocks, orphan ownership remains fenced. |
| T-06 local UI accepts arbitrary state | T `99ebc10`, `1b6b1a2` | `testRunningAndCancelledPlansCannotBeLocallyAccepted`, `testOfflineCannotAcceptDependenciesOrUnlockDispatch`, `testConflictRequiresFreshReviewInsteadOfAutomaticRetry` | Local/offline state cannot grant acceptance or unblock dependencies; conflict requires fresh review. |
| T-07 Plan creation/dispatch disconnected | T `99ebc10`, `1b6b1a2` | `testNewTaskImmediatelyHasOnlyAnUnacceptedDraftPlan`, `testCreateDispatchWaitAndAcceptThroughHTTP`, `testSaveAndStartAIExecutesAfterTaskSync` | New Task exposes Plan immediately; dispatch waits for sync and acceptance consumes actual HTTP receipt. F12 happy UI now selects both criteria. |
| T-08 feedback not really persisted | T `ad4e132`, `63923a0`, `e990fb7`; V `212ae62` | `testDraftContentAndKeySurviveRecreationAndAreScopedByAccountAndDraft`, `testFailedSubmissionPersistsBeforeNetworkAndReusesFrozenPayloadAndKey`, `testFeedbackHTTPFailureRestartRetryAndConfirmedCleanup` | Durable per-account draft/key survives restart; receipt confirms cleanup; account-bound requests cannot leak across login/logout. |
| T-09 production report ignores dedup | T `95940f5`, `c9f6206`, `f9a3a75` | `testSharedCrossMidnightFixtureMatchesServerTotals`, `testServerProjectionScopesFactsAndDedupesWithoutMergingParallelAttempts`, `testReportsUseServerFactsRevisionAndCoverageGate`, `testProjectReportUsesOnlyItsServerFacts` | Production report projection uses server day/zone/revision facts, clips scopes and preserves distinct parallel attempts; unknown differs from zero. |

F12 full-flow test is
`WorkspaceFlowTests.test_full_flow_quota_checkpoint_native_resume_accept_report`.
The permanent Go launcher is `TestWorkspacePythonIntegration`. CLI names are
from `cli/tests`, Swift names from `ios/KeJiTests` or
`ios/KeJiUITests/WorkspaceFlowTests.swift`, Go names from
`Valley/internal/apps/timetrace/*_test.go`.

The application-level integration has six Python tests. Go separately verifies
their original event observations against PostgreSQL; events are not seeded.
The iOS HTTP fixture is narrower UI contract evidence, never counted as this
real backend integration. Production billing/native-session/account guarantees
remain unverified until authorized real-subscription validation.
