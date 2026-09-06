# Design: tb-issue-finish worktree cleanup (KP-4)

## Overview

Restructure the cleanup step of `skills/tb-issue-finish/SKILL.md` so that removing the ticket worktree folder and deleting the ticket branch happen in every environment, while Herdr-specific workspace handling stays gated behind the `HERDR_ENV=1` check.

## Root Cause

In the current SKILL.md, step 6 ("Clean up the Herdr worktree") is introduced by a Herdr-only condition and its substeps remove the worktree via `herdr worktree remove` and the branch via `git branch -d` only inside that block. Outside Herdr (or when the workspace was not created by the Herdr automation), the whole cleanup is skipped, so `~/projects/worktrees/<repo-name>/<prefix>` and the local branch `<prefix>` survive a finished ticket.

## Architecture

Only the skill instructions change; no scripts or external tools are added.

The cleanup step becomes a two-part procedure:

1. **Git cleanup (always):**
   - Resolve the worktree path for branch `<prefix>` with `git worktree list --porcelain` (the same lookup used by the `wt-dir` helper in `tb-issue-finish/scripts/herdr-workspace.sh`).
   - Run all cleanup commands from the main repository checkout, resolved via `git rev-parse --path-format=absolute --git-common-dir` (its parent directory). This satisfies the "cannot remove the current worktree" constraint of `git worktree remove`.
   - Dirty check: if `git -C <worktree-path> status --porcelain` is non-empty, stop and ask the user. Never use `--force`.
   - Remove the worktree with `git worktree remove <path>` (git refuses if dirty — matching requirement 4).
   - Delete the branch with `git branch -d <prefix>` (`-d` refuses unmerged branches — matching requirement 5). Never `-D` without explicit user confirmation.
   - Missing worktree or branch is reported as already removed and the flow continues (idempotency).
2. **Herdr cleanup (conditional):** unchanged in spirit — only when `HERDR_ENV=1` and the workspace was created by this workflow, close the Herdr workspace and remove the Herdr-managed worktree entry via the `herdr` skill.

## Decision: inline commands vs. `wt-delete` helper

**Context:** The repo already ships `scripts/herdr-workspace.sh` with a `wt-delete` function covering worktree + branch + workspace deletion.

**Options considered:**
1. Have the skill source `herdr-workspace.sh` and call `wt-delete` — Pros: one code path, less SKILL.md text. Cons: `wt-delete` uses `git branch -D` and `rm -rf` unconditionally, violating the no-data-loss requirements; the skill would depend on sourcing a zsh function library from a possibly-absent path.
2. Inline guarded git commands in SKILL.md — Pros: each guard (dirty check, `-d` over `-D`, idempotency) is explicit and enforceable by the agent; no new dependencies. Cons: slightly longer skill text.

**Decision:** Option 2 — inline guarded commands in SKILL.md. The script remains available for manual use; tightening it is out of scope for this ticket.

## Error Handling

- Dirty worktree → stop, show `git -C <worktree> status --porcelain`, ask the user how to proceed; ticket status stays unchanged.
- Unmerged branch (`git branch -d` refuses) → stop and ask the user; never delete with `-D` unprompted.
- Missing worktree/branch → log "already removed" and continue to the Herdr substep and later steps.
- Any cleanup failure → do not mark the ticket `done`; report the failure (existing rule 4 of the skill).

## Testing Strategy

Manual walkthrough (the deliverable is a markdown skill, so verification is a dry-run review):

1. Confirm the git-cleanup instructions contain no `HERDR_ENV` gate.
2. Confirm the Herdr substep is still gated on `HERDR_ENV=1` and ownership of the workspace.
3. Simulate the idempotent path: run the worktree lookup for a branch with no worktree and confirm the instructions describe continuing.
4. Re-check that "close the ticket" remains the final step.
