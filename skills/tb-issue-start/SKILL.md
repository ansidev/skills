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
7. Worktree enforcement (HARD RULE): ALL implementation MUST happen inside a git worktree on a branch named `<prefix>` created off the default branch. NEVER read, edit, stage, or run any implementation step in the main repository checkout or on `main`/`master`. This applies even when `HERDR_ENV` is unset, when the user says "just do it here", or when worktree creation fails — in those cases you stop and report instead of falling back to the main checkout. This rule exists so multiple agents can work on tickets in parallel; violating it breaks every other in-flight ticket.
8. Before the first implementation step, and again after any `cd` or checkout, verify Rule 7 with the Worktree gate below. The gate is a stop condition, not a suggestion.
9. Naming (HARD RULE): `<prefix>` in this skill is the FULL ticket prefix — e.g. `KP-3`. The worktree folder name, git branch name, and herdr workspace label MUST all be exactly `<prefix>`. NEVER use the bare project prefix (the `projectPrefix` field on the ticket record, e.g. `KP`) as the worktree or branch name; it truncates the ticket suffix and collides across tickets of the same project.

## Input

1. Input is the taskboard ticket ID or ticket prefix.
2. If the input length is 26, it is considered a ticket ID. If the input length is shorter than 26, it is considered a ticket prefix.
3. `<prefix>` used for naming throughout this skill is resolved as follows:
   - Input is a ticket prefix (< 26 chars, e.g. `KP-3`): `<prefix>` is the input verbatim.
   - Input is a ticket ID (26 chars): `<prefix>` is `<projectPrefix>-<number>` from the retrieved ticket record (e.g. `KP-3`).
   - `<prefix>` is NEVER the bare `projectPrefix` value (e.g. `KP`); that field is for lookup/grouping only.

## Worktree gate (MUST pass before any implementation)

Run both checks; every later step of this skill runs only after both succeed:

1. You are inside a linked worktree, not the main checkout:

   ```bash
   test "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)"
   ```

2. You are on the ticket branch `<prefix>` (the full ticket prefix, e.g. `KP-3`), not the default branch and not the bare project prefix:

   ```bash
   test "$(git branch --show-current)" = "<prefix>"
   ```

If a check fails, fix it before continuing:

- Check 1 fails (you are in the main checkout): create the worktree under `${HOME}/projects/worktrees/<repo-name>/<prefix>`, then `cd` into it and re-run the gate.
  - Inside Herdr (`HERDR_ENV=1`): ensure `${HOME}/projects/worktrees/<repo-name>` exists (`mkdir -p "${HOME}/projects/worktrees/<repo-name>"`), then `herdr worktree create --branch <prefix> --label <prefix> --path "${HOME}/projects/worktrees/<repo-name>/<prefix>" --no-focus`, then `cd` into the created worktree directory reported in the JSON result (`result.worktrees[].path`).
  - Outside Herdr: resolve the default branch with `git symbolic-ref refs/remotes/origin/HEAD` (strip the remote prefix; fall back to `main` only after confirming with the user), ensure `${HOME}/projects/worktrees/<repo-name>` exists (`mkdir -p "${HOME}/projects/worktrees/<repo-name>"`), then `git fetch origin && git worktree add "${HOME}/projects/worktrees/<repo-name>/<prefix>" -b <prefix> <default-branch> && cd "${HOME}/projects/worktrees/<repo-name>/<prefix>"`.
- Check 2 fails but check 1 passes: locate the worktree for branch `<prefix>` with `git worktree list --porcelain` (or the `wt-dir` helper from `tb-issue-finish/scripts/herdr-workspace.sh`), `cd` into it, and re-run the gate. If no such worktree exists, treat it as check 1 failing.
- Wrong-name mismatch: IF an existing worktree or branch for this ticket was created under the bare project prefix (e.g. `KP` instead of `KP-3`), do NOT reuse, rename, or delete it silently — report the mismatch to the user and stop for their decision.
- Worktree creation fails: stop and report the error to the user. NEVER continue implementing in the main checkout as a fallback.

## Instructions

1. If user given a ticket prefix, run command `taskboard ticket list | grep <prefix>` to get the ticket ID. You should not ask user for the ticket ID if the user has already provided a ticket prefix.
2. Use tool `taskboard_get_ticket` to retrieve the ticket details with id is the given/resolved ticket ID. If the ticket is not found, return a message indicating that the ticket does not exist.
3. If the ticket status is todo, use tool `taskboard_update_ticket` to change the status to in_progress and team to agent. Otherwise, if the ticket status is in_progress, continue to the next step. If the ticket status is done, return a message indicating that the issue has already been resolved.
4. If the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the user asked to start the ticket from inside Herdr AND the Worktree gate does NOT pass yet (i.e., you are not already the agent running inside the ticket's worktree), run the Herdr automation workflow below. If the gate already passes, you ARE the spawned agent: skip the automation and continue with step 5.
5. Run the Worktree gate for ticket branch `<prefix>` (see above). This step MUST pass before any implementation step. All remaining steps run inside the worktree directory.
6. Important: MUST use skill `spec-driven-development` to create a solution for the issue.
7. Important rule: The output of phase 1 of the `spec-driven-development` skill (`Requirements Gathering`) MUST be updated back to the taskboard ticket description.
8. Additional steps as needed by the `spec-driven-development` skill to complete the solution.
9. When the implementation finishes, apply Rules 3 and 4: do not move the ticket to `done`; stage exactly the ticket-relevant changes without committing. First confirm with `git rev-parse --show-toplevel` that you are staging inside the ticket worktree, not the main checkout.

## Herdr automation workflow (only when `HERDR_ENV=1` and not already inside the ticket worktree)

Use this workflow to bootstrap the implementation environment automatically, replacing the manual steps (create worktree workspace → start pi agent → send the prompt).

1. Create the worktree workspace named by the full ticket prefix under `${HOME}/projects/worktrees/<repo-name>`, without stealing focus. For ticket KP-3 in repo `skills` this is literally `--branch KP-3 --label KP-3` — never `--branch KP`:

   ```bash
   mkdir -p "${HOME}/projects/worktrees/<repo-name>" && herdr worktree create --branch <prefix> --label <prefix> --path "${HOME}/projects/worktrees/<repo-name>/<prefix>" --no-focus
   ```

   Read the workspace ID and pane ID from the JSON result. On failure, report the error to the user and stop — do not start the agent, and do not implement the ticket yourself.
2. Start the cline coding agent in the worktree workspace's shell pane. On failure, report the error and leave the workspace for manual inspection.
3. Deliver the ticket prompt to the agent so it starts working in the new session:

   ```bash
   herdr agent prompt <agent-name> "/skill:tb-issue-start <prefix>"
   ```

   Optionally pass `--wait` to wait only until the agent settles after its first turn — never wait for the whole implementation.
4. Report the created workspace ID, pane ID, and agent name back to the user, then return control to them. Do not focus the workspace; the user will interact with the agent as needed and run skill `tb-issue-finish <prefix>` after reviewing the result.
