---
name: kp-issue-finish
description: Use this skill to finish a kanpal ticket after the user has manually reviewed and approved the implementation. When the user asks to finish, close out, land, or wrap up a kanpal ticket, this skill will be activated.
license: MIT
---

# kp-issue-finish

## When to use

Use this skill ONLY when the user explicitly asks to finish a kanpal ticket, after the user has manually reviewed the staged changes and confirmed the implementation is OK. This skill is the single place where a kanpal ticket may be moved to `done`.

## Rules

1. MUST use available tools from `kanpal` MCP.
3. Use skill `herdr` for all Herdr interactions. Before any `herdr` command, verify the agent runs inside Herdr with `test "${HERDR_ENV:-}" = 1`; if the check fails, skip only the Herdr workspace cleanup and tell the user — the git worktree and branch cleanup still runs.
4. NEVER set the ticket status to `done` until every prior step of this skill has succeeded.
5. NEVER force-push, force-merge, force-remove a worktree (`git worktree remove --force`), force-delete a branch (`git branch -D`), or auto-abort a rebase without asking the user.
6. MUST call tool `kanpal_get_ticket` with parameter `{"prefix": "<ticket-prefix>"}`.
6. MUST call tool `kanpal_update_ticket` with parameter `{"id":"<ticket-id>"}`.

## Instructions

1. The user input is ticket prefix.
2. Call tool `kanpal_get_ticket` to get the ticket information. If the ticket is not found, stop and say so.
3. Otherwise, read the `id` property from the tool result. It is the ticket ID (<ticket-id>).
4. If there are staged changes, commit the staged changes with a Conventional Commit message whose optional scope is the ticket prefix:

   ```
   <type>(<ticket-prefix>): <description>
   ```

   For example: `feat(AK-2): update kp-issue-start skill`. Infer `<type>` from the change (feat, fix, refactor, docs, test, chore, ...) and write a concise description summarizing the ticket title. Commit only what is staged (`git commit`, no `-a`).
5. If there is no staged changes, check the git commit history. If the git commit history indicates the changes was not commited, that's an issue, stop immediately and report the issue to user.
6. Rebase onto the base branch:
   1. If user does not provide the information, you MUST ask them and get their confirm before rebasing onto a guessed base. NEVER rebase without user confirmation. DO NOT overthinking or overconfidence.
   2. `git fetch <remote>` then `git rebase <base-branch>`.
   3. IF a git conflict occurs, stop processing immediately, show `git status`, and ask the user to resolve the conflict manually. Do not abort or continue the rebase yourself. The ticket status stays unchanged.
7. If the rebase succeeded, merge the changes back to the base branch: `git checkout <base-branch>` then `git merge <ticket-prefix>`. Verify with `git log`.
8. Clean up the ticket worktree and branch (run in EVERY environment), then close the Herdr workspace if applicable:
   1. Git cleanup — unconditional, never gated on the Herdr check:
      1. Resolve the worktree path for the ticket branch: `git worktree list --porcelain` and find the `worktree <path>` block whose `branch refs/heads/<ticket-prefix>` line matches the ticket branch.
      2. Resolve the main repository checkout: `git rev-parse --path-format=absolute --git-common-dir`, strip the trailing `/\.git`, and `cd` there. Run all remaining cleanup commands from the main checkout so `git worktree remove` never targets the worktree you are currently inside.
      3. IF the worktree was found, run `git -C <worktree-path> status --porcelain`. IF the output is not empty, stop and ask the user how to handle the leftover changes before deleting anything. Do not delete a dirty worktree yourself.
      4. Remove the worktree with `git worktree remove <worktree-path>` (never `--force`). If git reports the path does not exist, report that it was already removed and continue.
      5. Delete the ticket branch with `git branch -d <ticket-prefix>` (never `-D`). If git refuses because the branch is not fully merged, stop and ask the user. If the branch does not exist, report that it was already deleted and continue.
      6. Only touch the worktree and branch named `<ticket-prefix>` for this ticket; never remove worktrees or branches belonging to other tickets.
   2. Herdr cleanup — ONLY if the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the workspace was created by this workflow:
      1. Close the worktree workspace using the `herdr` skill (close/remove the workspace tab or use `herdr workspace close` as the installed binary supports).
      2. Run `herdr worktree remove --workspace <ID>` to remove the worktree.
      3. Only touch workspaces/worktrees this workflow created; never remove ones you did not create.
9. Add knowledge: use skill `add-knowledge` to record knowledge related to this ticket in the OpenKnowledge base (via the `kb-okf` MCP). Prefer updating an existing document; create a new one only when appropriate.
10. Close the ticket: update the kanpal ticket status to `done` using `kanpal_update_ticket`. Tool call input parameters are `id` (the ticket ID from step 3) and `status` = "done". This step must be last; if any earlier step failed, stop without changing the status and report the failure.
11. ONLY if the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the workspace was created by this workflow, then run `w=$(herdr workspace list | jq -r --arg v "$1" '.result.workspaces[] | select(.label == $v or .workspace_id == $v) | .workspace_id') && [[ -n "$w" ]] && herdr workspace close "$w" || echo "Workspace not found: $1" >&2` to close the herdr workspace.
12. Report to user what you have done as a checklist.
