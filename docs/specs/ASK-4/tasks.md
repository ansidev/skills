# ASK-4 — Tasks

- [ ] 1. Adapter completion (`skills/lib/host-runtime.sh`)
  - [ ] 1.1 `worktree-create` for herdr-tui (herdr worktree create), herdr-desktop + outside (git-native)
  - [ ] 1.2 `worktree-lookup` for all runtimes
  - [ ] 1.3 `workspace-close` TUI adapter (resolve workspace via lookup, then close)
  - _Requirements: 3, 4, 7, 8_
- [ ] 2. SKILL.md routing
  - [ ] 2.1 kp-issue-new: delegate confirmed starts to `kp-issue-start` (no `start-issue`, no host commands)
  - [ ] 2.2 kp-issue-start: runtime-agnostic automation workflow via `host-runtime detect|worktree-create|agent-start|agent-prompt`; worktree gate points at `worktree-create`; no `HERDR_ENV` gating or `wt-switch`
  - [ ] 2.3 kp-issue-finish: cleanup via `worktree-lookup` + `workspace-close`; git cleanup unconditional; no `wt-del`, `ws-id`, `herdr-workspace.sh`
  - _Requirements: 1, 2, 4, 5, 6, 7_
- [ ] 3. Tests
  - [ ] 3.1 Contract tests for the new ops (per-runtime, stubbed binaries; git-native worktree on a fixture repo)
  - [ ] 3.2 Skill-text routing test: no host binaries or removed function names in any kp-issue SKILL.md
  - _Requirements: 1–9_
- [ ] 4. Validation and handoff
  - [ ] 4.1 Run full test suite; commit issue-relevant files; set issue to `in-review`
