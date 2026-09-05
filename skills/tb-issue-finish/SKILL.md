---
name: tb-issue-finish
description: Use this skill to finish a taskboard ticket after the user has manually reviewed and approved the implementation. When the user asks to finish, close out, land, or wrap up a taskboard ticket, this skill will be activated.
license: MIT
---

# tb-issue-finish

## When to use

Use this skill ONLY when the user explicitly asks to finish a taskboard ticket, after the user has manually reviewed the staged changes and confirmed the implementation is OK. This skill is the single place where a taskboard ticket may be moved to `done`.

## Rules

1. Use the MCP tools of the MCP called `taskboard`.
2. Use skill `tb-cli` to fetch information not available via MCP.
3. Use skill `herdr` for all Herdr interactions. Before any `herdr` command, verify the agent runs inside Herdr with `test "${HERDR_ENV:-}" = 1`; if the check fails, skip Herdr cleanup and tell the user.
4. Never set the ticket status to `done` until every prior step of this skill has succeeded.
5. Never force-push, force-merge, or auto-abort a rebase without asking the user.

## Input

1. Input is the taskboard ticket ID or ticket prefix.
2. If the input length is 26, it is considered a ticket ID. If the input length is shorter than 26, it is considered a ticket prefix.

## Instructions

1. Resolve the ticket: if given a ticket prefix, run `taskboard ticket list | grep <prefix>` to get the ticket ID; otherwise use the given ticket ID. Retrieve details with `taskboard_get_ticket`. If the ticket is not found, stop and say so.
2. Guard rails: inspect the staged changes with `git status --porcelain` and `git diff --cached --stat`. If nothing is staged, stop and tell the user to review and stage the relevant changes first. Do not stage anything yourself in this skill.
3. Commit the staged changes with a Conventional Commit message whose optional scope is the ticket prefix:

   ```
   <type>(<prefix>): <description>
   ```

   For example: `feat(AK-2): update tb-issue-start skill`. Infer `<type>` from the change (feat, fix, refactor, docs, test, chore, ...) and write a concise description summarizing the ticket title. Commit only what is staged (`git commit`, no `-a`).
4. Rebase onto the base branch:
   1. Resolve the base branch properly: prefer the repo default branch via `git symbolic-ref refs/remotes/origin/HEAD` (strip the remote prefix); if unavailable, use `main` and confirm with the user before rebasing onto a guessed base.
   2. `git fetch <remote>` then `git rebase <base-branch>`.
   3. IF a git conflict occurs, stop processing immediately, show `git status`, and ask the user to resolve the conflict manually. Do not abort or continue the rebase yourself. The ticket status stays unchanged.
5. If the rebase succeeded, merge the changes back to the base branch: `git checkout <base-branch>` then `git merge <prefix-branch>`. Verify with `git log`. Then return to the working branch state expected by later steps (stay on the base branch for cleanup).
6. Clean up the Herdr worktree (only if running inside Herdr and the workspace was created by this workflow):
   1. Close the worktree workspace using the `herdr` skill (close/remove the workspace tab or use `herdr workspace close` as the installed binary supports).
   2. Run `herdr worktree remove --workspace <ID>` to remove the worktree, and delete the feature branch with `git branch -d <prefix-branch>` from the main repo root.
   3. Only touch workspaces/worktrees this workflow created; never remove ones you did not create.
7. Add knowledge: use skill `add-knowledge` to record knowledge related to this ticket in the OpenKnowledge base (via the `kb-okf` MCP). Prefer updating an existing document; create a new one only when appropriate.
8. Close the ticket: update the taskboard ticket status to `done` using `taskboard_update_ticket` (or the `taskboard` CLI via `tb-cli` if MCP is unavailable). This step must be last; if any earlier step failed, stop without changing the status and report the failure.
