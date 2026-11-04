# Requirements: repair Herdr TUI workspace discovery

## User story

- As an operator closing an issue workspace, I want the Herdr adapter to
  identify a workspace from its nested checkout path, so that the intended
  workspace closes instead of being silently reported absent.

## Acceptance criteria

1. WHEN `herdr workspace list` returns a workspace whose
   `worktree.checkout_path` equals the supplied or discovered Git worktree
   path, THEN `worktree-lookup` SHALL return that workspace's `workspace_id`.
2. WHEN `workspace-close` finds a matching nested checkout path, THEN the
   adapter SHALL invoke `herdr workspace close <workspace_id>` and report
   `closed: 1` with that ID.
3. WHEN no nested checkout path matches, THEN lookup SHALL return a null
   workspace ID and close SHALL return a confirmed no-workspace result without
   invoking a close command.
4. WHEN `herdr workspace list` fails, THEN lookup and close SHALL return an
   adapter error that is distinct from an absent workspace; close SHALL not
   report successful cleanup.
5. WHEN parsing Herdr list output, THEN lookup and close SHALL use the same
   JSON-aware mapping of `workspace_id` and `worktree.checkout_path`.
6. WHEN the adapter changes, THEN regression tests SHALL cover matching,
   absent, and list-failure responses using representative nested Herdr JSON.

## Constraints

- Preserve the existing runtime envelope conventions.
- Match checkout paths exactly; do not close an unrelated workspace.
- Keep this change limited to the Herdr TUI adapter and its tests.
