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
3. Use skill `herdr` for all Herdr interactions. Before any `herdr` command, verify the agent runs inside Herdr with `test "${HERDR_ENV:-}" = 1`; if the check fails, skip only the Herdr workspace cleanup and tell the user — the git worktree and branch cleanup still runs.
4. Never set the ticket status to `done` until every prior step of this skill has succeeded.
5. Never force-push, force-merge, force-remove a worktree (`git worktree remove --force`), force-delete a branch (`git branch -D`), or auto-abort a rebase without asking the user.

## Input

1. Input is the taskboard ticket ID or ticket prefix. These are two different strings with different lengths and MUST NOT be conflated:
   - **Ticket prefix**: the project prefix, e.g. `KP` (the `projectPrefix` field on the ticket record). It is shared by every ticket of the project, so it alone never identifies a single ticket. It is for lookup/grouping only.
   - **Ticket ID**: the per-ticket identifier in short form `<prefix>-<number>`, e.g. `KP-3` (this is what `taskboard ticket list` shows in brackets, e.g. `[KP-3]`). The taskboard MCP/CLI additionally expose an internal 26-character ULID (e.g. `01M1VSVYDCNW26SMBDRVN6AT5M`) for the same ticket.
2. Recognise the input by its shape:
   - Matches `^[A-Z]+-[0-9]+$` (e.g. `KP-3`): it is a ticket ID (short form) — NOT a prefix.
   - Is a 26-character uppercase alphanumeric string (ULID): it is a ticket ID (internal form).
   - Is a bare alphabetic string without a `-<number>` part (e.g. `KP`): it is a ticket prefix.
3. If the input is a ticket prefix, do NOT treat it as a ticket ID. Run `taskboard ticket list | grep <prefix>` to list that project's tickets. If exactly one ticket matches, use it; if several match, ask the user which ticket number they mean. NEVER use the bare prefix as a ticket ID, worktree name, or branch name.
4. `<ticket-id>` used throughout this skill is the ticket ID in short form `<prefix>-<number>` (e.g. `KP-3`), resolved as follows:
   - Input is a ticket ID short form: `<ticket-id>` is the input verbatim.
   - Input is an internal ULID, or the ticket was resolved from a prefix: `<ticket-id>` is `<projectPrefix>-<number>` from the retrieved ticket record.
   - `<ticket-id>` is NEVER the bare ticket prefix value (`projectPrefix`, e.g. `KP`); that field is for lookup/grouping only.

## Instructions

1. Resolve the ticket: if given a ticket ID short form, run `taskboard ticket list | grep <ticket-id>` to get the internal ULID; if given an internal ULID, use it; if given a bare ticket prefix, follow Input rule 3. Retrieve details with `taskboard_get_ticket` using the internal ULID. If the ticket is not found, stop and say so.
2. Guard rails: inspect the staged changes with `git status --porcelain` and `git diff --cached --stat`. If nothing is staged, stop and tell the user to review and stage the relevant changes first. Do not stage anything yourself in this skill.
3. Commit the staged changes with a Conventional Commit message whose optional scope is the ticket ID:

   ```
   <type>(<ticket-id>): <description>
   ```

   For example: `feat(AK-2): update tb-issue-start skill`. Infer `<type>` from the change (feat, fix, refactor, docs, test, chore, ...) and write a concise description summarizing the ticket title. Commit only what is staged (`git commit`, no `-a`).
4. Rebase onto the base branch:
   1. Resolve the base branch properly: prefer the repo default branch via `git symbolic-ref refs/remotes/origin/HEAD` (strip the remote prefix); if unavailable, use `main` and confirm with the user before rebasing onto a guessed base.
   2. `git fetch <remote>` then `git rebase <base-branch>`.
   3. IF a git conflict occurs, stop processing immediately, show `git status`, and ask the user to resolve the conflict manually. Do not abort or continue the rebase yourself. The ticket status stays unchanged.
5. If the rebase succeeded, merge the changes back to the base branch: `git checkout <base-branch>` then `git merge <ticket-id>`. Verify with `git log`.
6. Clean up the ticket worktree and branch (run in EVERY environment), then close the Herdr workspace if applicable:
   1. Git cleanup — unconditional, never gated on the Herdr check:
      1. Resolve the worktree path for the ticket branch: `git worktree list --porcelain` and find the `worktree <path>` block whose `branch refs/heads/<ticket-id>` line matches the ticket branch.
      2. Resolve the main repository checkout: `git rev-parse --path-format=absolute --git-common-dir`, strip the trailing `/\.git`, and `cd` there. Run all remaining cleanup commands from the main checkout so `git worktree remove` never targets the worktree you are currently inside.
      3. IF the worktree was found, run `git -C <worktree-path> status --porcelain`. IF the output is not empty, stop and ask the user how to handle the leftover changes before deleting anything. Do not delete a dirty worktree yourself.
      4. Remove the worktree with `git worktree remove <worktree-path>` (never `--force`). If git reports the path does not exist, report that it was already removed and continue.
      5. Delete the ticket branch with `git branch -d <ticket-id>` (never `-D`). If git refuses because the branch is not fully merged, stop and ask the user. If the branch does not exist, report that it was already deleted and continue.
      6. Only touch the worktree and branch named `<ticket-id>` for this ticket; never remove worktrees or branches belonging to other tickets.
   2. Herdr cleanup — ONLY if the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the workspace was created by this workflow:
      1. Close the worktree workspace using the `herdr` skill (close/remove the workspace tab or use `herdr workspace close` as the installed binary supports).
      2. Run `herdr worktree remove --workspace <ID>` to remove the worktree.
      3. Only touch workspaces/worktrees this workflow created; never remove ones you did not create.
7. Add knowledge: use skill `add-knowledge` to record knowledge related to this ticket in the OpenKnowledge base (via the `kb-okf` MCP). Prefer updating an existing document; create a new one only when appropriate.
8. Close the ticket: update the taskboard ticket status to `done` using `taskboard_update_ticket` (or the `taskboard` CLI via `tb-cli` if MCP is unavailable). This step must be last; if any earlier step failed, stop without changing the status and report the failure.
9. Report to user what you have done as a checklist.
