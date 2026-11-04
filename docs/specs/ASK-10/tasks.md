# Tasks: repair Herdr TUI workspace discovery

- [x] 1. Add failing nested-JSON regression tests
  - Replace legacy flat workspace fixtures with `worktree.checkout_path` data.
  - Add absent-workspace and list-command-failure coverage for lookup and
    close, including the assertion that close is never attempted on failure.
  - _Requirements: 1-6_

- [x] 2. Introduce the shared JSON-aware workspace matcher
  - Add one helper in `skills/lib/host-runtime.sh` that returns an exact
    workspace ID for a nested checkout path.
  - Route both TUI lookup and close through it and distinguish list failures
    from confirmed absence.
  - _Requirements: 1-5_

- [x] 3. Synchronize vendored adapter copies
  - Apply the canonical adapter change to the start and finish skill copies
    only if the repository's tests or distribution conventions require the
    copies to stay byte-identical.
  - _Requirements: 5_

- [x] 4. Verify and deliver
  - Run targeted and full tests, review the issue diff, commit only issue
    files, and transition ASK-10 to `in-review`.
  - _Requirements: 1-6_
