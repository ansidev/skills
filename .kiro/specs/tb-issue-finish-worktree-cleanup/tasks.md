# Tasks: tb-issue-finish worktree cleanup (KP-4)

- [ ] 1. Rework the cleanup step in `skills/tb-issue-finish/SKILL.md`
  - [ ] 1.1 Make git worktree + branch cleanup unconditional (no `HERDR_ENV` gate), per requirements 1–2
  - [ ] 1.2 Add the main-checkout execution guard so `git worktree remove` never targets the current worktree, per requirement 3
  - [ ] 1.3 Add the dirty-worktree stop-and-ask guard and the `git branch -d` (never `-D`) guard, per requirements 4–5
  - [ ] 1.4 Keep idempotent "already removed" handling and ticket-scoped-only cleanup, per requirements 6 and 8
  - [ ] 1.5 Keep the Herdr workspace close/remove substep gated on `HERDR_ENV=1` and workspace ownership, per requirement 7
  - _Requirements: 1, 2, 3, 4, 5, 6, 7, 8_
- [ ] 2. Verify the updated skill against the design walkthrough (manual dry-run review)
  - _Requirements: 1–8_
