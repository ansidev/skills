# ASK-5 — Requirements: Verify and document extensible host-runtime support

## Goal

Prove the runtime integration boundary (`skills/lib/host-runtime.sh`) and issue-skill behavior work for the initial Herdr adapters (TUI, Desktop) and the outside-host case, and remain safe and understandable as future hosts are added.

## User stories

1. As a skill maintainer, I want contract tests for runtime detection and adapter capabilities, so that an unsupported or regressed adapter implementation fails before a skill regression reaches users.
2. As a skill maintainer, I want behavior tests for `kp-issue-new`, `kp-issue-start`, and `kp-issue-finish` across herdr-tui, herdr-desktop, and outside-host cases, so that skill routing works on every supported host.
3. As a skill maintainer, I want deterministic tests that do not depend on live workspaces, sidebar order, or hard-coded IDs, so the suite passes on any machine.
4. As a future host integrator, I want the adapter contract documented with a procedure for adding a new host, so that extension means adding an adapter, not branching existing code.

## Acceptance criteria (EARS)

1. WHEN the test suite runs THEN the system SHALL execute in a hermetic environment: the result envelope, runtime detection, and adapter selection SHALL NOT depend on the invoking shell's `HERDR_ENV`, PATH contents, cwd, or live Herdr state.
2. IF a detection state is ambiguous (TUI signal without `herdr`, Desktop app without reachable `hc`) THEN the boundary SHALL report a `DETECT_FAILED` envelope and the tests SHALL assert it.
3. WHEN `host-runtime` is invoked outside any host THEN agent/prompt operations SHALL return `NO_HOST_AGENT` without executing any host command, and the tests SHALL assert via call-log that no host binary ran.
4. WHEN the test suite runs against each runtime (herdr-tui, herdr-desktop, outside) THEN the worktree, agent, and close operations SHALL be exercised with stubbed binaries and asserted on the exact constructed commands and parsed output.
5. WHEN `worktree-create` runs under herdr-desktop or outside THEN the system SHALL create a real git worktree under `HR_WORKTREE_ROOT/<repo>/<issue-key>` on a branch named exactly `<issue-key>`, verified on a fixture git repo.
6. IF an adapter does not support an operation (e.g. `worktree-remove` under herdr-tui) THEN the system SHALL return `RUNTIME_UNSUPPORTED` and the tests SHALL assert the refusal.
7. WHEN the three issue scripts run THEN the tests SHALL verify skill-text routing: every SKILL.md delegates through the shared boundary and none references removed function names (`wt-switch`, `ws-id`, `wt-del`, `start-issue`) or direct host command construction.
8. WHEN `workspace-close` runs under any runtime THEN the system SHALL close only resources scoped to the issue (label `herdr.issue=<key>` on Desktop, resolved workspace id on TUI) and the tests SHALL assert scoping from the call log.
9. WHEN the test suite finishes THEN the project's standard validation command (`python3 -m unittest discover -s tests`) SHALL pass from a clean environment.
10. WHEN a maintainer wants to support a new host THEN `docs/host-runtime.md` SHALL document the detection signals, the envelope contract, per-op command mappings, error codes, and a step-by-step procedure to add a new adapter (new runtime id + `hr_<op>_<runtime>` functions + detection wiring + tests), not merely a branch inside existing adapters.
11. IF the host-runtime library changes shape (new op, new envelope field, removed error code) THEN the contract tests SHALL fail, forcing a documentation update alongside.
