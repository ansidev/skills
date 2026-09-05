---
name: tb-issue-start
description: Use this skill to start working on the solution for the relevant taskboard issue. When the user asks to fix, correct, or start an issue in the taskboard, this skill will be activated.
license: MIT
---

# tb-issue-start

## When to use

Use this skill when the user asks to fix, correct, or resolve an issue in the taskboard. This skill will be activated to start working on the solution for the relevant taskboard issue.

## Rules

1. Use the MCP tools of the MCP called `taskboard`.
2. Use skill `tb-cli` to fetch information not available via MCP.
3. Never set a ticket status to `done` in this skill. Closing a ticket is reserved for skill `tb-issue-finish`, which the user runs explicitly after manual review.
4. When the implementation work finishes, stage exactly the ticket-relevant files with `git add <files>`; never commit or push, and never stage unrelated files, temp artifacts, or scratch output.
5. Before any `herdr` command, verify this agent runs inside Herdr with `test "${HERDR_ENV:-}" = 1`; if the check fails, say you are not running inside Herdr and do not issue herdr commands.
6. Parse workspace/pane/agent IDs from herdr JSON responses; never derive them from examples or sidebar order. Use `--no-focus`/`--current` for background work.

## Input

1. Input is the taskboard ticket ID or ticket prefix.
2. If the input length is 26, it is considered a ticket ID. If the input length is shorter than 26, it is considered a ticket prefix.

## Instructions

1. If user given a ticket prefix, run command `taskboard ticket list | grep <prefix>` to get the ticket ID. You should not ask user for the ticket ID if the user has already provided a ticket prefix.
2. Use tool `taskboard_get_ticket` to retrieve the ticket details with id is the given/resolved ticket ID. If the ticket is not found, return a message indicating that the ticket does not exist.
3. If the ticket status is todo, use tool `taskboard_update_ticket` to change the status to in_progress and team to agent. Otherwise, if the ticket status is in_progress, continue to the next step. If the ticket status is done, return a message indicating that the issue has already been resolved.
4. If the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the user asked to start the ticket from inside Herdr, run the Herdr automation workflow below. Otherwise continue with step 5.
5. Important: MUST use skill `spec-driven-development` to create a solution for the issue.
6. Important rule: The output of phase 1 of the `spec-driven-development` skill (`Requirements Gathering`) MUST be updated back to the taskboard ticket description.
7. Additional steps as needed by the `spec-driven-development` skill to complete the solution.
8. When the implementation finishes, apply Rules 3 and 4: do not move the ticket to `done`; stage exactly the ticket-relevant changes without committing.

## Herdr automation workflow (only when `HERDR_ENV=1`)

Use this workflow to bootstrap the implementation environment automatically, replacing the manual steps (create worktree workspace → start pi agent → send the prompt).

1. Create the worktree workspace named by the ticket prefix, without stealing focus:

   ```bash
   herdr worktree create --branch <prefix> --label <prefix> --no-focus
   ```

   Read the workspace ID and pane ID from the JSON result. On failure, report the error to the user and stop — do not start the agent.
2. Start the cline coding agent in the worktree workspace's shell pane. On failure, report the error and leave the workspace for manual inspection.
3. Deliver the ticket prompt to the agent so it starts working in the new session:

   ```bash
   herdr agent prompt <agent-name> "/skill:tb-issue-start <prefix>"
   ```

   Optionally pass `--wait` to wait only until the agent settles after its first turn — never wait for the whole implementation.
4. Report the created workspace ID, pane ID, and agent name back to the user, then return control to them. Do not focus the workspace; the user will interact with the agent as needed and run skill `tb-issue-finish <prefix>` after reviewing the result.
