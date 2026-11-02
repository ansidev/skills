# ASK-3 — Tasks

- [x] 1. Shared runtime library
  - [x] 1.1 `skills/lib/host-runtime.sh`: detection (`hr_detect_runtime`), envelope (`hr_envelope`), dispatch (`hr_run`), error codes
  - [x] 1.2 Adapters: `worktree-create`, `worktree-lookup`, `agent-start`, `agent-prompt`, `workspace-close` for `herdr-tui`, `herdr-desktop`, `outside`
  - _Requirements: 1–14_
- [x] 2. CLI entry point
  - [x] 2.1 `skills/lib/host-runtime` executable with the documented subcommands and JSON-only stdout
  - _Requirements: 7–9_
- [x] 3. Skill integration
  - [x] 3.1 `kp-issue-new`, `kp-issue-start`, `kp-issue-finish`: `script.sh` becomes a thin wrapper over the library (public function names preserved)
  - [x] 3.2 SKILL.md text: generalize TUI-only wording; "unknown runtime → stop and report"; worktree HARD RULE unchanged
  - _Requirements: 1–5, 10–14_
- [x] 4. Tests
  - [x] 4.1 `tests/test_host_runtime.bash`: detection matrix, envelope shape, adapters with stubbed binaries, cleanup scoping
  - [x] 4.2 Standalone runner + CI-friendly invocation
  - _Requirements: 7–14_
- [x] 5. Validation and handoff
  - [x] 5.1 Run tests, shellcheck-style review, commit issue-relevant files, set issue to `in-review`
  - _Requirements: all_
