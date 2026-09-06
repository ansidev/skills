# Requirements: tb-issue-finish worktree cleanup (KP-4)

## Overview

`tb-issue-finish` currently performs worktree cleanup only inside Herdr. When the finish flow runs outside Herdr, the ticket's git worktree folder and its branch are left behind. This spec makes worktree and branch cleanup unconditional (with Herdr workspace close remaining Herdr-only) and adds safety guards against data loss.

## User Story

As a developer using the taskboard workflow, after finishing a ticket with `tb-issue-finish` I want the ticket's git worktree folder and its branch removed, so that leftover worktrees and branches do not accumulate whether I run inside or outside Herdr.

## Acceptance Criteria (EARS)

1. WHEN the cleanup step is reached in the `tb-issue-finish` flow THEN the skill SHALL remove the git worktree directory associated with the ticket branch `<prefix>` (located via `git worktree list --porcelain`), regardless of whether `HERDR_ENV=1`.
2. WHEN the worktree removal succeeds THEN the skill SHALL delete the ticket branch `<prefix>` from the repository, regardless of whether `HERDR_ENV=1`.
3. IF the flow is running inside the worktree being removed THEN the skill SHALL execute the cleanup from the main repository checkout so `git worktree remove` does not fail on the current worktree.
4. IF the worktree contains uncommitted or untracked changes at cleanup time THEN the skill SHALL stop and ask the user instead of force-removing the worktree (no data loss).
5. IF the ticket branch is not fully merged into the base branch THEN the skill SHALL refuse deletion (`git branch -d`, never `-D`) and ask the user.
6. WHEN the worktree or branch does not exist at cleanup time THEN the skill SHALL report it as already removed and continue (idempotent cleanup).
7. IF the flow runs inside Herdr AND the workspace was created by this workflow THEN the skill SHALL additionally close the Herdr workspace and remove the Herdr-managed worktree entry.
8. The skill SHALL never remove worktrees, branches, or workspaces that are not associated with the current ticket's `<prefix>`.

## Constraints

- Do not change when the ticket is moved to `done`; closing remains the last step and only after every prior step succeeds.
- Do not modify the ticket commit/rebase/merge steps of the skill; scope is limited to cleanup.
- Never force-remove a dirty worktree or force-delete an unmerged branch without explicit user confirmation.
