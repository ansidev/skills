---
name: kp-issue-finish
description: Use this skill to finish a kanpal issue after the user has manually reviewed and approved the implementation. When the user asks to finish, close out, land, or wrap up a kanpal issue, this skill will be activated.
license: MIT
---

# kp-issue-finish

## When to use

Use this skill ONLY when the user explicitly asks to finish a kanpal issue, after the user has manually reviewed the staged changes and confirmed the implementation is OK. This skill is the single place where a kanpal issue may be moved to `done`.

## Arguments

Invocation: `/kp-issue-finish --issue <issue-key> --base <base-branch> [--cancel] [-y]`

| Argument   | Required                          | Value                                                |
| ---------- | --------------------------------- | ---------------------------------------------------- |
| `--issue`  | always                            | `<issue-key>`, e.g. `KAN-10`                         |
| `--base`   | only when `--cancel` is NOT given | `<base-branch>`, e.g. `develop` or `origin/develop`  |
| `--cancel` | optional flag, takes no value     | when present, cancel the issue instead of merging it |
| `-y`       | optional flag, takes no value     | when present, proceed automatically without confirmation prompts, given all required inputs are provided |

Parsing rules:

- Parse `<issue-key>` from the token after `--issue` and `<base-branch>` from the token after `--base`. Arguments may appear in any order.
- `--cancel` is detected by its presence only. Set `IS_CANCEL=true` when given, otherwise `false`.
- If `--issue` is missing or has no value, ask the user for the issue key (do not guess).
- If `--cancel` is not given and `--base` is missing, ask the user for the base branch and get their confirmation (do not guess).
- If `--cancel` is given, `--base` is ignored and not required.
- `-y` is detected by its presence only. Set `AUTO_YES=true` when given, otherwise `false`.
- When `AUTO_YES=true` and all required inputs (`--issue`, and `--base` unless `--cancel`) are provided, proceed automatically: skip the plan confirmation (Merge workflow step 1.1) and any other "confirm before continuing" prompt. Do not ask for approval, just run the workflow.
- With `-y`, ask the user only when information is missing or a decision cannot be made safely, e.g. missing `--issue` or `--base`, unstaged/untracked changes, an unresolvable rebase conflict, a failed fast-forward, a dirty main checkout or worktree, a branch git refuses to delete, or an unknown repo path. `-y` never authorizes the forced operations forbidden in Rules; those still need explicit user confirmation.

## Rules

1. MUST use available tools from `kanpal` MCP.
2. Follow the Cancel workflow when `--cancel` is given; otherwise follow the Merge workflow.
3. Use the shared `skills/lib/host-runtime` adapter for host lifecycle operations. It detects `herdr-tui`, `herdr-desktop`, or `outside`; an `unknown` result is a stop condition and must never cause a fallback command path. Host cleanup is skipped only for `outside`; git worktree and branch cleanup remains mandatory.
4. NEVER set the issue status to `done` (Merge workflow) or `cancelled` (Cancel workflow) outside this skill, and never set `done` until every prior step of this skill has succeeded.
5. NEVER force-push, force-merge, force-remove a worktree (`git worktree remove --force`), force-delete a branch (`git branch -D`), or auto-abort a rebase unless user confirms or it is defined explicitly in the skill instructions. The only such exception is the Cancel workflow, which MUST clean up with forced removal (it force-removes the worktree and branch by design through the host adapter).
6. MUST call tool `kanpal_get_issue` with parameter `{"key": "<issue-key>"}`.
7. MUST call tool `kanpal_update_issue` with parameter `{"id":"<issue-id>"}`.

## Cancel workflow (`--cancel` given)

Do NOT commit, rebase, or merge the issue worktree branch, and do NOT add knowledge.

1. Call tool `kanpal_get_issue` with `{"key": "<issue-key>"}`. If the issue is not found, stop and say so. Read `id` from the result (<issue-id>).
2. Update the issue status: call `kanpal_update_issue` with `{"id": "<issue-id>", "status": "cancelled"}`. If the call fails, stop and report the failure; do not clean up.
3. Clean up the host agent (if any): run `bash <skill-directory>/../lib/host-runtime workspace-close --issue <issue-key>` (best-effort; report any `RUNTIME_UNSUPPORTED`/`NO_HOST_AGENT` error but do not stop). Then clean up the git worktree and branch (Cancel workflow only, forced by design): `(cd <main-checkout> && bash <skill-directory>/../lib/host-runtime worktree-remove --issue <issue-key> --force)`. The adapter uses `wt remove` when worktrunk is installed, plain `git worktree remove` + `git branch -D` otherwise. Run from the main checkout, never inside the worktree being removed. Only touch paths named `<issue-key>`.
4. Report to the user what you have done as a checklist.

## Merge workflow (`--cancel` not given)

Use `<issue-key>` and `<base-branch>` from the arguments. Ask only for values that are missing. Never push.

The skill may be started from ANY directory (main checkout, the worktree, or elsewhere). Never rely on the current directory: resolve `<main-checkout>` and `<worktree-path>` in step 1, then run every git command with `git -C <worktree-path> ...` (issue branch work) or `git -C <main-checkout> ...` (base branch work and cleanup). Do not `cd`.

1. Pre-flight:
   1. Confirm the plan with the user (once; when `AUTO_YES=true`, skip the confirmation, just state the plan and continue): rebase and fast-forward merge `<issue-key>` onto `<base-branch>`, then clean up its worktree, branch and Herdr workspace. NEVER rebase or merge onto a guessed base.
   2. Resolve `<main-checkout>`: `git rev-parse --path-format=absolute --git-common-dir`, strip the trailing `/.git`. If the current directory is not inside a git repo, ask the user for the repo path. Then resolve `<worktree-path>`: `git -C <main-checkout> worktree list --porcelain`, the `worktree <path>` block whose `branch refs/heads/<issue-key>` matches. If none is found, stop and report (if the branch exists without a worktree, ask the user).
   3. Call `kanpal_get_issue` with `{"key": "<issue-key>"}`. If not found, stop and say so. Read `id` (<issue-id>). If the status is already `done` or `cancelled`, stop and report.
   4. If running under a managed host, resolve the host workspace ID of `<issue-key>` now (while the worktree still exists) with `bash <skill-directory>/../lib/host-runtime worktree-lookup --issue <issue-key>` and remember it as `<workspace-id>` (empty if none). Otherwise remember there is none.
2. Commit:
   1. Run `git -C <worktree-path> status --porcelain`. If there are unstaged or untracked changes, ask the user how to handle them before continuing. Never use `git add -A` or `git commit -a`.
   2. If there are staged changes, commit only them (`git -C <worktree-path> commit`) with a Conventional Commit message whose scope is the issue key:

      ```
      <type>(<issue-key>): <description>
      ```

      For example: `feat(AK-2): update kp-issue-start skill`. Infer `<type>` (feat, fix, refactor, docs, test, chore, ...) and write a concise description summarizing the issue title.
   3. If nothing is staged, verify `git -C <worktree-path> log <base-branch>..<issue-key>` has commits. If it has none, the work was never committed: stop and report. If it has commits, continue (rerun case).
3. Rebase:
   1. If `<base-branch>` is a remote ref (e.g. `origin/develop`), run `git -C <worktree-path> fetch <remote>` for that remote only. If the fetch fails, stop and report.
   2. Use skill `wt-rebase` (`/wt-rebase --base <base-branch> --worktree-path <worktree-path>`), which rebases the branch checked out in the issue worktree. NEVER run `git rebase` directly.
   3. If `wt-rebase` cannot complete (unresolvable conflict, failed check, or it asks the user), stop, show `git -C <worktree-path> status`, and report. Do not abort the rebase yourself. The issue status stays unchanged.
4. Merge from the main checkout:
   1. All commands in this step use `git -C <main-checkout>`. Let `<local-base>` be `<base-branch>` without the remote prefix (`origin/develop` -> `develop`).
   2. Verify `git -C <main-checkout> status --porcelain` is empty in the main checkout; otherwise stop and ask the user.
   3. `git -C <main-checkout> checkout <local-base>`. If `<local-base>` is behind its remote counterpart, fast-forward it (`git -C <main-checkout> merge --ff-only <remote>/<local-base>`); if it cannot be fast-forwarded, stop and ask the user.
   4. `git -C <main-checkout> merge --ff-only <issue-key>`. If it fails, stop and report (do not create a merge commit).
   5. Verify: `git -C <main-checkout> merge-base --is-ancestor <issue-key> <local-base>` must succeed. If the merge was already done in a previous run, this check passes and you continue.
5. Git cleanup (never gated on the Herdr check; use `git -C <main-checkout>` so the removal never targets a directory you are inside):
   1. Use `<worktree-path>` from step 1.2 (re-run `git -C <main-checkout> worktree list --porcelain` if unsure; if it is no longer listed, it was already removed).
   2. If it still exists, run `git -C <worktree-path> status --porcelain`. If not empty, stop and ask the user before deleting anything.
   3. Remove it with `bash <skill-directory>/../lib/host-runtime worktree-remove --issue <issue-key>` (no `--force`; the adapter uses `wt remove` when worktrunk is installed, plain `git worktree remove` + `git branch -D` otherwise). If the adapter reports `WORKTREE_NOT_FOUND`, report it as already removed and continue.
   4. Delete the branch with `git -C <main-checkout> branch -d <issue-key>` (never `-D`). If git refuses because it is not fully merged, stop and ask the user. If the branch does not exist, report it as already deleted and continue.
   5. Only touch the worktree and branch named `<issue-key>`.
6. Add knowledge: use skill `add-knowledge` to record knowledge related to this issue in the OpenKnowledge base (via the `kb-okf` MCP). Prefer updating an existing document; create a new one only when appropriate. Issue notes live at the content-dir-relative path `projects/kanpal/<issue-key-lowercase>-<slug>` (on disk `knowledge/projects/kanpal/...`). NEVER write the path as `knowledge/projects/...` or `knowledge/knowledge/...`, and do not copy the location of an existing misplaced note. If this step fails, warn, continue, and mention it in the report.
7. Close the issue: call `kanpal_update_issue` with `{"id": "<issue-id>", "status": "done"}`. Only do this if steps 1-5 all succeeded; otherwise stop without changing the status and report the failure.
8. Host cleanup (last, because it may close the session you are running in). Only if a `<workspace-id>` was resolved in step 1.4, regardless of who created the workspace:
   1. Print the step 9 report FIRST (as the final message content), then run `bash <skill-directory>/../lib/host-runtime workspace-close --issue <issue-key>`.
   2. Never touch workspaces belonging to other issues.
9. Report to the user what you have done as a checklist (commit, rebase, merge, worktree/branch cleanup, knowledge, status, Herdr cleanup, plus any skipped or warned steps).
