# ASK-3 — Requirements: Host-runtime integration boundary for issue skills

Source: kanpal issue ASK-3. Format: EARS.

## User stories

1. As an agent running the `kp-issue-*` skills inside **Herdr TUI**, I want the same workflow to keep working unchanged, so that my automation (worktree workspace, agent launch, prompting, cleanup) is preserved.
2. As an agent running the `kp-issue-*` skills under **Herdr Desktop**, I want the workflow to drive the correct binaries (`herdr-app` for window-side state, `hc` for terminals and agents), so that I am not forced through TUI-only commands that do not exist there.
3. As an agent running the skills **outside any managed host**, I want a plain-git worktree flow with no Herdr calls, so that worktree isolation still holds.
4. As an agent in an **unresolvable runtime state** (e.g. `herdr-app` present but `hc` unreachable, or `HERDR_ENV=1` without the `herdr` binary), I want a clear, actionable error and a stop, so that I never silently fall back to an unsafe command path.
5. As a skill maintainer, I want to add a new host by writing one adapter plus contract tests, so that `kp-issue-new/start/finish` do not each need edits.

## Acceptance criteria (EARS)

Runtime detection (single contract, explicit outcomes: `herdr-tui` | `herdr-desktop` | `outside` | `unknown`):

1. WHEN `HERDR_ENV=1` AND the `herdr` binary is on PATH THEN the runtime SHALL be detected as `herdr-tui`.
2. IF `HERDR_ENV=1` AND the `herdr` binary is missing THEN the runtime SHALL be `unknown` with an error identifying the failed signal.
3. WHEN `HERDR_ENV` is unset AND `herdr-app` is on PATH AND `hc server status` succeeds THEN the runtime SHALL be `herdr-desktop`.
4. IF `herdr-app` is on PATH AND `hc` is missing or `hc server status` fails THEN the runtime SHALL be `unknown` with an error identifying the failed signal.
5. IF none of the managed-host signals are present THEN the runtime SHALL be `outside`.
6. WHEN detection runs THEN it SHALL NOT depend on sidebar ordering, example IDs, or guessed state; it SHALL use environment variables and binary/version probes only.

Normalized result shape (one shape for every runtime and operation):

7. WHEN any adapter operation completes THEN it SHALL print one JSON envelope on stdout: `{"ok":true,"runtime":"<runtime>","op":"<op>","data":{...}}` on success or `{"ok":false,"runtime":"<runtime>","op":"<op>","error":{"code":"...","message":"..."}}` on failure.
8. WHEN an operation fails THEN the envelope SHALL identify the runtime, the failed operation, and a stable error code.
9. WHEN a host command returns JSON THEN the adapter SHALL parse identifiers (workspace, pane, terminal) from that structured response, never from examples or positional guesses.

Adapter operations (used by kp-issue-new / kp-issue-start / kp-issue-finish):

10. WHEN a caller needs the issue worktree THEN the adapter SHALL support worktree creation and lookup, keeping Git worktree isolation independent of host integration (an unsupported host SHALL NOT weaken worktree rules).
11. WHEN a caller needs to run or prompt an agent THEN the adapter SHALL support terminal/pane selection, agent launch, and prompt delivery through the selected runtime's native commands (TUI: `herdr` CLI; Desktop: `hc`, with `herdr-app` for window-side commands).
12. WHEN a caller finishes an issue THEN the adapter SHALL support workspace/terminal cleanup scoped to that issue's resources only.

Extensibility and behavior:

13. WHEN a new host is added THEN it SHALL require only a new adapter implementation plus contract tests, not edits to each issue skill's workflow text.
14. IF the detected runtime is `unknown` THEN the skills SHALL stop and report the error; they SHALL NOT fall back to TUI or Desktop commands.

## Out of scope

- Supporting any third host.
- Changing the Kanpal workflow or relaxing worktree-isolation rules.
