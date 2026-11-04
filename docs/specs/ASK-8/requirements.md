# Requirements: complete `kp-issue-finish` closeout verification

## User stories

- As an operator rerunning closeout for a terminal issue, I want every closeout obligation checked again so that incomplete cleanup is visible.
- As an operator with local scratch files, I want safe merges and rebases to continue without changing unrelated untracked files.
- As a maintainer, I want cleanup constrained to the issue key so that other branches, worktrees, workspaces, and files stay intact.

## Acceptance criteria

1. WHEN an issue is `done` or `cancelled`, THEN `kp-issue-finish` SHALL run its closeout checklist and report evidence or explicit N/A for each item.
2. WHEN any terminal-issue checklist item cannot be verified, THEN the skill SHALL report that result and SHALL NOT give an unqualified completion claim.
3. WHEN host cleanup applies, THEN the skill SHALL use its vendored `host-runtime` adapter, act only on issue-owned resources, and verify absence as the final item.
4. WHEN the runtime is `outside`, THEN host cleanup SHALL be reported as N/A.
5. WHEN untracked base-checkout files are unrelated to paths written by a rebase, fast-forward merge, or cleanup, THEN the skill SHALL continue and preserve them.
6. WHEN an untracked path would be overwritten or conflicts with the requested operation, THEN the skill SHALL stop before mutation and name the conflicting path.
7. WHEN cleanup runs, THEN the skill SHALL leave unrelated worktrees, workspaces, branches, and untracked files untouched.

## Constraints

- Unknown host runtime detection remains a stop condition.
- Existing no-force safety rules remain unchanged outside explicit cancel behavior.
- A missing worktree or workspace counts as clean only after a fresh lookup.
