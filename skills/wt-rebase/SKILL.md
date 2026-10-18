---
name: wt-rebase
description: Use this skill to rebase the current git branch on top of a base branch, resolve any code conflicts, and fix migration file name conflicts. Invoked as `/wt-rebase --base <base_branch> [--worktree-path <worktree_path>]`. Trigger whenever the user asks to rebase the current branch onto a base branch, continue an in-progress rebase, or fix migration name collisions after a rebase.
license: MIT
---

# wt-rebase

Rebase the current branch (or the branch checked out in `--worktree-path`, when given) on top of `<base_branch>`, resolve conflicts, and make sure migration file names do not collide with ones introduced by the base branch.

## Arguments

Invocation: `/wt-rebase --base <base_branch> [--worktree-path <worktree_path>]`

- Parse the value that follows `--base` (also accept `--base=<base_branch>`). Example: `--base main` → `<base_branch>` = `main`.
- Value is a single branch/ref name (e.g. `main`, `origin/main`, `develop`).
- If `--base` is missing or has no value, ask the user for the base branch. Do not guess.
- `--worktree-path <worktree_path>` is optional (also accept `--worktree-path=<worktree_path>`). It is the directory of the worktree whose checked-out branch should be rebased, so the skill can be started from any directory.
  - If given, verify it is a git worktree (`git -C <worktree_path> rev-parse --show-toplevel`); if not, report it and stop. Then run EVERY git command in this skill as `git -C <worktree_path> ...`, read and edit files under `<worktree_path>`, and never `cd` or touch the current directory's repository.
  - If omitted, use the current directory and plain `git` commands.
  - In the rest of this skill, `git ...` means `git -C <worktree_path> ...` when `--worktree-path` is given.
- Verify the ref exists: `git rev-parse --verify --quiet <base_branch>` (with `-C <worktree_path>` when given). If not, report it and stop.

## Checklist

Report each item as done before finishing:

1. Rebasing started.
2. Rebasing completed.
3. No code conflict.
4. No migration file name conflict.

## Safety rules

- Do not run `git reset --hard`, `git clean -fdx`, `git push --force`, or `git rebase --skip` / `--abort` unless the user asks.
- Do not push. Leave the result local.
- If the working tree has uncommitted changes and no rebase is in progress, stop and ask the user (commit/stash first) rather than stashing silently.
- Preserve the intent of both sides when resolving conflicts; never resolve by blindly taking one side unless the other side is clearly obsolete.

## Workflow

### 1. Start (or continue) the rebase

Detect whether a rebase is already in progress:

```sh
git rev-parse --git-path rebase-merge   # directory exists → in progress
git rev-parse --git-path rebase-apply   # directory exists → in progress
```

(Or check `git status` for "rebase in progress".)

- **Rebase already in progress:** do NOT run `git rebase <base_branch>` again. Go to step 2 (check for conflicts, then `git rebase --continue`).
- **No rebase in progress:** run `git rebase <base_branch>`. Remember the pre-rebase tip (`git rev-parse ORIG_HEAD` after, or record `git rev-parse HEAD` before) and the merge base (`git merge-base HEAD <base_branch>` before rebasing) — step 3 needs them.

### 2. Resolve code conflicts

Loop until the rebase finishes:

1. `git status` — list unmerged paths (`git diff --name-only --diff-filter=U`).
2. For each conflicted file, read it, understand both sides (`ours` = base branch commits being replayed onto, `theirs` = the current branch's commit being applied), and edit it to a correct merged result with no conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
3. Verify no markers remain: `git diff --check` and `grep -rn '^<<<<<<<\|^>>>>>>>' <files>`.
4. `git add <resolved files>`.
5. `GIT_EDITOR=true git rebase --continue`.
6. Repeat if the next commit conflicts too.

Migration files may conflict here as well; handle them per step 3 rather than by merging contents.

Finish when `git status` no longer reports a rebase in progress.

### 3. Check and fix migration file name conflicts

Context: branches A and B are checked out from the same base. Both may add a migration with the same name/number/timestamp prefix (e.g. `0042_add_users.sql`, or the same version number). If A is merged into the base first, B's migration must be renamed after rebasing so it sorts after, and does not collide with, the base's migration.

Procedure:

1. Find the migration directories (look for `migrations/`, `db/migrate/`, `migrate/`, `alembic/versions/`, `prisma/migrations/`, `drizzle/`, etc.; check project docs/config for the convention).
2. List migrations added by the current branch: `git diff --name-status --diff-filter=A <merge_base>..<pre_rebase_tip> -- <migration dirs>` (if rebase was already in progress and the values were not recorded, use `git diff --name-status --diff-filter=A <base_branch>...HEAD`).
3. List migrations added by the base since the merge base: `git diff --name-status --diff-filter=A <merge_base>..<base_branch> -- <migration dirs>`.
4. Detect conflicts, any of:
   - identical file names;
   - same sequence number / version / timestamp prefix (e.g. two `0042_*`);
   - the branch's migration sorts before or equal to the latest base migration, breaking ordering;
   - migration chain/head metadata that must be linear (e.g. Alembic `down_revision`, Django `dependencies`, Atlas/`atlas.sum`, Prisma `migration_lock`) now has two heads or points to the wrong parent.
5. Fix by renaming the **current branch's** migrations (never the base's), keeping their relative order:
   - Use `git mv` to rename to the next free number/timestamp after the base's latest migration, following the project's naming format.
   - Update everything that references the old name: dependency/parent pointers inside the migration, revision IDs, checksum/sum files (regenerate with the project's tool, e.g. `atlas migrate hash`), schema snapshot/manifest files, and tests/docs.
   - Do not modify migrations that already exist on the base branch.
6. Re-list the migration directory and confirm all names/versions are unique and ordered, and the chain has a single head.
7. Commit the rename. If the rebase is complete, make a new commit (e.g. `fix: rename migration to resolve conflict after rebase`) or amend the commit that introduced the migration if it is clearly the right place; tell the user which you chose. Do not rewrite unrelated commits.

If the project has no migrations, mark checklist item 4 as "n/a (no migrations)".

### 4. Verify and report

- `git status` clean, no rebase in progress; `git log --oneline <base_branch>..HEAD` shows the branch commits on top of the base.
- Run the project's quick checks if obvious (build/lint/tests, or migration validation command) when cheap; report if skipped.

Final report, in checklist form:

1. Rebasing started — yes/no (or "already in progress").
2. Rebasing completed — yes/no.
3. No code conflict — list files that conflicted and how they were resolved (or none).
4. No migration file name conflict — list renames (old → new) and reference updates (or none).

Mention that the branch history was rewritten, so pushing will need `--force-with-lease`, but do not push.
