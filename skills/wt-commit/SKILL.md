---
name: wt-commit
description: Use this skill when a task is finished and its changes need to be committed — either in a git worktree on a detached HEAD (commit the pending changes and cherry-pick the commit onto <base_ref>, the branch the worktree was created from) or directly on the main/base branch (commit in place). Trigger whenever the user asks to commit worktree changes, land worktree changes onto a branch, finish a worktree-based task by moving its commit to <base_ref>, or commit finished task work on the main branch.
license: MIT
---

# wt-commit

## When to use

The task is finished and its changes need to be committed and landed. Two contexts are supported:

- **Worktree context:** you are in a git worktree on a detached HEAD. Commit the working changes and land the commit onto `<base_ref>`, which is the branch the task worktree was created from.
- **Main-branch context:** you are already on the base branch (for example `main`) in the main worktree. Commit the pending task changes in place; no cherry-pick or stash is needed.

`<base_ref>` is the branch the task worktree was created from, or simply the current branch in the main-branch context. If the user did not state it explicitly, infer it from the worktree setup (for example the taskboard issue's base branch, or the fork point recorded when the worktree was created); if it cannot be determined, ask.

## Safety rules

- Do not run destructive commands: `git reset --hard`, `git clean -fdx`, `git worktree remove`, or `rm`/`mv` on repository paths.
- Do not edit files outside git workflows unless required for conflict resolution.
- Preserve any pre-existing user uncommitted changes in the base worktree.

## Steps

0. Determine the context by running `git rev-parse --abbrev-ref HEAD` and `git rev-parse --git-dir`:
   - Detached HEAD → worktree context; follow steps 1–9.
   - On a branch in the main worktree (`.git-dir` does not contain `worktrees/`) → main-branch context: stage and commit the pending task changes directly on this branch, then report the commit hash, commit message, whether conflicts were resolved, and any remaining manual follow-up. Skip the stash/cherry-pick steps.
   - On a branch inside a linked worktree (`.git-dir` contains `worktrees/`) → treat it like the worktree context, using the current branch as `<base_ref>` if it is already the task's base branch, otherwise follow steps 1–9.

1. In the current task worktree, stage and create a commit for the pending task changes.
2. Find where `<base_ref>` is checked out:
   - Run `git worktree list --porcelain`.
   - If branch `<base_ref>` is checked out in path P, use that P.
   - If not checked out anywhere, use the current worktree as P by checking out `<base_ref>` there.
3. In P, verify the current branch is `<base_ref>`.
4. If P has uncommitted changes, stash them and record the new stash's SHA so you only ever pop the entry you created:
   - `git -C P stash push -u -m "wt-commit-pre-cherry-pick"`
   - `STASH_SHA=$(git -C P rev-parse stash@{0})`
5. Cherry-pick the task commit into P. If this fails because `.git/index.lock` exists, wait briefly for any active git process to finish. If the lock remains and no git process is active, treat the lock as stale, remove it, and retry.
6. If the cherry-pick conflicts, resolve carefully, preserving both the intended task changes and existing user edits, then `git -C P cherry-pick --continue`.
7. If step 4 created a stash entry, restore it with `git -C P stash apply "$STASH_SHA"`, then drop it:
   - `git stash pop` refuses a bare SHA — it only accepts reflog references like `stash@{0}`, so use `apply` with the recorded SHA.
   - Drop with `git -C P stash drop stash@{0}` only after verifying `git -C P rev-parse stash@{0}` still equals `$STASH_SHA`; if the top of the stack changed, stop and report instead of dropping.
8. If the stash apply conflicts, resolve them while preserving pre-existing user edits.
9. Report:
   - Final commit hash
   - Final commit message
   - Whether stash was used
   - Whether conflicts were resolved
   - Any remaining manual follow-up needed

## Notes

- Cherry-pick (rather than merge or rebase) is deliberate: it moves exactly one task commit and leaves unrelated base-worktree history untouched.
- The `-u` in the stash push is required so untracked files in the base worktree are not lost during the cherry-pick.
- Only pop a stash entry you created in step 4; never pop a pre-existing user stash.
