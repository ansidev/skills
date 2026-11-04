# Tasks: complete `kp-issue-finish` closeout verification

- [ ] 1. Add failing skill-contract tests
  - Cover terminal statuses, full checklist reporting, host cleanup verification, and untracked-file conflict classification.
  - _Requirements: 1-7_

- [ ] 2. Restructure the finish workflow
  - Define the checklist and terminal-status verification branch in `skills/kp-issue-finish/SKILL.md`.
  - _Requirements: 1-4, 7_

- [ ] 3. Make Git preflight path-aware
  - Permit unrelated untracked files and stop only for a prospective overwrite/conflict, with an actionable path.
  - _Requirements: 5-6_

- [ ] 4. Verify and deliver
  - Run targeted and full tests, review the diff, commit only issue files, and move ASK-8 to `in-review`.
  - _Requirements: 1-7_
