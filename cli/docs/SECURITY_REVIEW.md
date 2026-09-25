# Security review: keji runner (`cli/keji`)

Date: 2026-09-25 · Scope: everything under `cli/` at commit `d19b2da`, with the
fixes landed in the commits listed per finding. Reviewed against Claude Code
2.1.281 and Codex CLI 0.155.1 on macOS.

## Threat model

| Actor | Trust | What they can do by design |
| --- | --- | --- |
| The Mac user who installed keji and owns the phone account | trusted | everything |
| Valley (the KeJi cloud) or anyone who takes over the phone account | semi-trusted | send prompts that an AI tool executes inside the sandbox of a registered repository |
| Repository content, issue text, files the model reads | untrusted | prompt injection: steer the model within its sandbox |
| The model's own output | untrusted | whatever the sandbox and permission mode allow |
| The network | untrusted | observe and tamper with traffic |
| Other local macOS users | untrusted | read files that permissions let them read |

Security goals: a remote task can only **write inside its own worktree** (plus
the git paths a commit needs), **cannot push**, **cannot switch a tool to
metered billing**, and nothing **secret** leaves the computer except the
runner's own Valley token (to Valley) and Claude Code's OAuth token (to
`api.anthropic.com`, for the quota read).

`SAFETY_RULES` in `adapters/base.py` is advisory text for the model. It is not
a control; the controls are listed in "How a remote prompt is contained" below.

## Findings

| ID | Severity | Location | Status |
| --- | --- | --- | --- |
| H-1 | High | `adapters/codex.py` `_writable_extras` | Fixed `802ea13` |
| H-2 | High | `worktree.py`, `agent.py` (runner git calls in a model-written directory) | Fixed `802ea13` |
| H-3 | High | `adapters/codex.py` `build_cmd` (resume) | Fixed `802ea13` |
| H-4 | High | `adapters/claude.py` `build_cmd` (prompt as last argv) | Fixed `ec64727` |
| H-5 | High | `adapters/claude.py` (project settings in the worktree) | Fixed `ec64727` |
| M-1 | Medium | `agent.py` completed/failed events, `process.py` `tail_text` | Mitigated `a370670` |
| M-2 | Medium | `process.py` `run_streaming` environment | Fixed `b9da8ee` |
| M-3 | Medium | `cloud.py`, `adapters/claude_usage.py` | Fixed `8e9a84b` |
| M-4 | Medium | `config.py` `ensure_dirs` (`~/.keji` permissions) | Fixed `a370670` |
| L-1 | Low | `cli.py` `cmd_agent_install` | Fixed `510593e`, `2ec6002` |
| L-2 | Low | `agent.py` log path from server job id | Fixed `510593e` |
| L-3 | Low | `db.py` outbox retention | Fixed `510593e` |
| L-4 | Low | `credentials.py` Keychain item ACL | Accepted |
| L-5 | Low | `tiers.py` account digests | Accepted |
| L-6 | Low | `db.py` `remote_claim.prompt` retention | Open |
| I-1 … I-6 | Info | see below | — |

### H-1 Codex sandbox could write the main repository's `.git`

*Scenario.* Codex ran with `--add-dir <main repo>/.git` so that `git commit`
works in a linked worktree. That made the **shared** `.git/config` and
`.git/hooks/` writable from the sandbox. A hostile prompt, or prompt injection
from repository content, could set `core.fsmonitor = <command>` or drop a
`pre-commit` hook. The next unsandboxed git process runs it with full user
rights and network: the runner's own `git diff` (checkpoint on a quota block)
or the user's next `git status`/`git commit` in the main checkout.

*Fix.* The sandbox now gets only what a commit writes: the worktree's admin
dir (`.git/worktrees/<name>`), `.git/objects`, and the directory of its branch
ref and reflog (`refs/heads/keji`, `logs/refs/heads/keji`)
(`worktree.sandbox_write_roots`). Verified with `codex sandbox`: the commit
succeeds; writes to `.git/config`, `.git/hooks` and `refs/heads/main` fail.
Codex itself keeps `<worktree>/.git` read-only.

### H-2 Runner ran git in a directory the model had rewritten

*Scenario.* Even with H-1 fixed, the model can write the worktree (including
its `.git` pointer file for Claude's edit tools) and, for Codex, the
per-worktree admin dir (`config.worktree`, `commondir`). Pointing `.git` or
`commondir` at an attacker-made directory, or adding `core.fsmonitor` /
`include.path` / a filter driver to `config.worktree`, turns the runner's next
git call in that worktree (snapshot, resume preparation) into command
execution outside the sandbox.

*Fix.* `worktree.verify_metadata(path, repo)` runs before every runner git call
in an execution worktree after a model run (checkpoint capture, resume
preparation in `ensure`, resume verification in `agent`). It requires that
`.git` is a regular file pointing into the **registered** repository's
`worktrees/` dir, that `commondir` resolves back to that repository, and that
`config.worktree` holds nothing but the runner's own `remote.*.pushurl =
no_push://blocked` lines. Tampering blocks the job with a
`checkpoint … metadata changed` reason for manual review. The runner's git calls
there also pass `-c core.fsmonitor=false -c core.hooksPath=/dev/null` and
`--no-ext-diff` (`worktree.SAFE_GIT`).

### H-3 Codex resume ran without an explicit sandbox, and failed with `--add-dir`

*Scenario.* `codex exec resume` accepts neither `-s` nor `--add-dir`. The
resume command omitted the sandbox, so a resumed run used whatever
`~/.codex/config.toml` said (possibly `danger-full-access`), and every resume
in a linked worktree failed with "unexpected argument '--add-dir'".

*Fix.* Both start and resume pass `-c sandbox_mode="<sandbox>"`,
`-c sandbox_workspace_write.writable_roots=[…]` and
`-c sandbox_workspace_write.network_access=false` (argument parsing verified
against the installed Codex). Network off also makes `git push <url>` fail
inside the sandbox.

### H-4 A phone prompt starting with `-` was parsed as a Claude Code option

*Scenario.* The prompt is the last argv element of `claude -p …`. A prompt
such as `--settings={"hooks":{"SessionStart":[…]}}` or
`--permission-mode=bypassPermissions` is read by Claude Code's option parser as
a flag: command execution outside the permission model, triggered by whoever
can create a task (Valley or the phone account).

*Fix.* `adapters/claude.safe_positional` prefixes a space to a prompt that
starts with `-`. (Codex's prompt always starts with `SAFETY_RULES`.)

### H-5 Claude Code loaded project settings from the worktree

*Scenario.* In `-p` mode Claude Code skips the workspace-trust dialog and
loads `.claude/settings.json` / `.claude/settings.local.json` from the working
directory. Repository content, or a previous task's commit that a dependent
task builds on, could add hooks or `permissions.allow: ["Bash(*)"]`.

*Fix.* Unattended runs pass `--setting-sources user` (config key
`claude.setting_sources`, default `"user"`). The user's own
`~/.claude/settings.json` still applies.

### M-1 Secrets could leave the computer in run output

*Scenario.* Codex's sandbox can read the whole disk and Claude's stream-json
log contains tool results. A task (hostile or just unlucky: `cat .env`) puts a
credential into the log; the last 8000 bytes (`output_tail`), the model's final
message (`result_summary`) and error messages were uploaded to Valley
verbatim.

*Mitigation.* `keji/redact.py` masks provider token shapes (AWS/Aliyun key
ids, GitHub, OpenAI, Anthropic, Slack, Google, npm, Stripe), JWTs, PEM
private-key blocks (including blocks cut by the tail and JSON-escaped ones),
bearer/basic auth, URL passwords and secret-named assignments. `Agent._outbound`
applies it to every event field before the durable enqueue, so the outbox never
stores unmasked text, and re-bounds the tail to 8000 bytes. `upload_output_tail
= false` sends no tail at all. *Residual risk:* secrets in unknown formats, or
paraphrased by the model, are not detected; the model can still read files it
should not (reads are not sandboxed by either tool).

### M-2 Secret-named environment variables reached the AI tools

*Scenario.* Started from a shell, the runner passed its whole environment
(minus billing keys) to the tools: `GITHUB_TOKEN`, `AWS_SECRET_ACCESS_KEY`,
`NPM_TOKEN`… were readable by model-run commands and could be echoed into
uploaded output or used by a tool with network.

*Fix.* `process.run_streaming` drops every variable whose name contains
TOKEN, SECRET, PASSWORD/PASSWD, API_KEY, ACCESS_KEY, PRIVATE_KEY or
CREDENTIAL, in addition to `CLAUDE*` and the billing keys.

### M-3 Valley client: redirects, plain http, unbounded responses

*Scenario.* urllib follows redirects and copies ordinary request headers,
including `Authorization`, to the new location, also cross-host and
https→http. A `cloud_base_url` of `http://…` was accepted, sending refresh and
access tokens in clear text. `response.read()` was unbounded (a hostile or
broken server could exhaust memory). Server-supplied attempt ids were
interpolated into URL paths unescaped. The Claude usage call had the same
redirect behaviour for the OAuth token.

*Fix.* `CloudClient` requires `https` (plain `http` only for loopback test
servers), uses an opener that refuses every 3xx, sends the token with
`add_unredirected_header`, caps bodies at 1 MiB and percent-escapes path
segments. `claude_usage` uses the same opener and a 256 KiB cap. TLS
verification uses Python's default context (certificate and hostname checked).

### M-4 `~/.keji` was readable by other local users

*Scenario.* The data dir was created `0755` and files `0644`. macOS homes are
`0750` with group `staff`, and every local user is in `staff`, so another
account on the Mac could read prompts, run logs, the outbox and the task
worktrees.

*Fix.* `config.ensure_dirs` sets `~/.keji` to `0700` on every command.
`config.json` written by `keji config set` is `0600`.

### Low

- **L-1** The LaunchAgent plist was built by string replacement without XML
  escaping; a home path with `&` or `<` produced a broken plist. Now generated
  with `plistlib`.
- **L-2** The server-supplied job id was used in the log file name. Traversal
  failed only because `logs/remote-..` does not exist; the id is now reduced to
  `[A-Za-z0-9_-]`.
- **L-3** Acknowledged outbox rows (with output tails) were kept forever; they
  are now deleted 7 days after delivery. Unsent rows are kept until sent.
- **L-4** The runner's refresh token is a login-Keychain item created by the
  Python interpreter without a custom ACL; other code run by the same user
  through the same interpreter can read it without a prompt. Inherent to a
  user-level agent; accepted. Access tokens are never persisted.
- **L-5** Quota pools carry an 8-hex SHA-256 prefix of the tool's account id
  (unsalted). Not reversible for random account UUIDs; lets Valley group two
  computers on one account, which is the purpose. Accepted.
- **L-6** `remote_claim` keeps every received prompt in `keji.db`
  indefinitely. Local only (and `0700` now); retention not yet implemented.

### Info

- **I-1 Containment of a remote prompt.** Claude: `--permission-mode
  acceptEdits`, Bash limited to the `allowed_tools` git commands (no push),
  project settings ignored, prompt kept positional. Codex: seatbelt
  `workspace-write`, network off, writable roots limited to the worktree and
  its commit paths. Both: separate worktree per job, all remotes'
  `pushurl = no_push://blocked` in the worktree config, zero-spend gate
  re-checked before every spawn, billing variables removed. If the user widens
  `permission_mode` (e.g. `bypassPermissions`), `allowed_tools`, `sandbox` or
  `extra_args`, these guarantees no longer hold; that is an explicit choice.
- **I-2 Transport.** Timeouts: Valley 30 s, usage endpoint 15 s, `auth status`
  / `login status` 20 s, Codex app-server 15 s. No certificate pinning.
- **I-3 Credential reads** (`tiers.py`, `claude_usage.py`). Only the plan tier
  string and opaque digests leave `tiers.py`; the Keychain secret is read from
  `security … -w` stdout (never argv) and not logged. The OAuth access token
  goes only to the hard-coded `https://api.anthropic.com/api/oauth/usage`, and
  never when expired.
- **I-4 Pairing.** The QR code holds only the 8-character user code and the
  display name; the device code is never printed. Someone who gets a victim to
  approve *their* code binds the attacker's computer to the victim's account
  and would receive the victim's prompts; the phone must show computer name
  and platform before "确认绑定" (app/server side).
- **I-5 Zero spend.** Unchanged and sound: verdict from `claude auth status` /
  `codex login status`, API-key variables removed from every child, re-check
  with the cache bypassed immediately before a spawn.
- **I-6 Known cosmetic issue.** `--disallowedTools "Bash(git push*)"` uses the
  glob form; the documented prefix form is `Bash(git push:*)`. Push is not in
  the allow list, so it is denied either way.

## Verification

- Unit tests for every fix (`tests/test_worktree.py`, `test_codex_adapter.py`,
  `test_claude_adapter.py`, `test_cloud.py`, `test_claude_usage.py`,
  `test_redact.py`, `test_agent.py`, `test_process.py`, `test_config.py`,
  `test_cli.py`, `test_db.py`).
- Sandbox behaviour checked with `codex sandbox -c … -- sh -c '…'` on Codex
  0.155.1: commit in a linked worktree succeeds with the narrowed roots;
  `.git/config`, `.git/hooks`, other branch refs and the worktree's `.git` file
  are not writable; network is unreachable.
