"""Durable checkpoints and the natural-recovery decision.

A checkpoint captures just enough to resume the *same* provider session in the
*same* canonical workspace after a quota block — never secrets or the CLI
environment. Resume is only ever the original tool/session; a different tool or a
missing native session is not a resume.
"""
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List

CHECKPOINT_SCHEMA_VERSION = 1


@dataclass
class Checkpoint:
    plan_id: str
    job_id: str
    attempt_id: str
    tool_profile_id: str
    provider_session_id: str
    canonical_workspace: str
    git_head: str
    dirty_paths_digest: str
    last_output_offset: int
    completed_criteria: List[str]
    side_effect_summary: str
    reason: str
    schema_version: int = CHECKPOINT_SCHEMA_VERSION

    def to_row(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_row(cls, row: Dict[str, Any]) -> "Checkpoint":
        allowed = {f: row[f] for f in cls.__dataclass_fields__ if f in row}
        return cls(**allowed)


def resume_allowed(original_profile: str, requested_profile: str, native_resume: bool) -> bool:
    """A resume must keep the same tool profile and rely on a real native resume;
    the session context does not travel across tools, and there is no honest
    'fake resume' when the tool cannot continue a session."""
    return bool(original_profile) and original_profile == requested_profile and native_resume


@dataclass(frozen=True)
class ResumeInputs:
    cancelled: bool
    original_profile: str
    requested_profile: str
    native_resume: bool
    auto_resume_enabled: bool
    zero_spend_verified: bool
    availability: str  # available / blocked / unknown
    reliable_reset_passed: bool
    probe_used: bool
    has_native_session: bool


def resume_decision(inputs: ResumeInputs) -> str:
    """The natural-recovery state machine, as a pure decision.

    Returns one of:
      no_resume     - cancelled: the wake generation is invalid, never restart.
      waiting_input - no native session, or a cross-tool / non-native request.
      refresh_only  - auto-resume off: quota may be refreshed but nothing starts.
      resume        - fresh sample says available (+ zero-spend verified).
      probe         - unknown but a reliable reset passed; one controlled probe.
      wait          - blocked, unknown without a reliable reset, a spent probe,
                      or no verified zero-spend guarantee.
    """
    if inputs.cancelled:
        return "no_resume"
    if not inputs.has_native_session:
        return "waiting_input"
    if not resume_allowed(inputs.original_profile, inputs.requested_profile, inputs.native_resume):
        return "waiting_input"
    if not inputs.auto_resume_enabled:
        return "refresh_only"
    if not inputs.zero_spend_verified:
        return "wait"
    if inputs.availability == "available":
        return "resume"
    if inputs.availability == "unknown" and inputs.reliable_reset_passed and not inputs.probe_used:
        return "probe"
    return "wait"
