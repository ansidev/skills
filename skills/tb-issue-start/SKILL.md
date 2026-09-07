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
7. Worktree enforcement (HARD RULE): ALL implementation MUST happen inside a git worktree on a branch named `<ticket-id>` created off the default branch. NEVER read, edit, stage, or run any implementation step in the main repository checkout or on `main`/`master`. This applies even when `HERDR_ENV` is unset, when the user says "just do it here", or when worktree creation fails — in those cases you stop and report instead of falling back to the main checkout. This rule exists so multiple agents can work on tickets in parallel; violating it breaks every other in-flight ticket.
8. Before the first implementation step, and again after any `cd` or checkout, verify Rule 7 with the Worktree gate below. The gate is a stop condition, not a suggestion.
9. Naming (HARD RULE): the worktree folder name, git branch name, and herdr workspace label MUST all be exactly the ticket ID `<ticket-id>` (e.g. `KP-3`). NEVER use the bare ticket prefix (the `projectPrefix` field on the ticket record, e.g. `KP`) as the worktree, branch, or label name; the prefix drops the ticket number and collides across tickets of the same project.

## Input

1. Input is the taskboard ticket ID or ticket prefix. These are two different strings with different lengths and MUST NOT be conflated:
   - **Ticket prefix**: the project prefix, e.g. `KP` (the `projectPrefix` field on the ticket record). It is shared by every ticket of the project, so it alone never identifies a single ticket. It is for lookup/grouping only.
   - **Ticket ID**: the per-ticket identifier in short form `<prefix>-<number>`, e.g. `KP-3` (this is what `taskboard ticket list` shows in brackets, e.g. `[KP-3]`). The taskboard MCP/CLI additionally expose an internal 26-character ULID (e.g. `01M1VSVYDCNW26SMBDRVN6AT5M`) for the same ticket.
2. Recognise the input by its shape:
   - Matches `^[A-Z]+-[0-9]+$` (e.g. `KP-3`): it is a ticket ID (short form) — NOT a prefix.
   - Is a 26-character uppercase alphanumeric string (ULID): it is a ticket ID (internal form).
   - Is a bare alphabetic string without a `-<number>` part (e.g. `KP`): it is a ticket prefix.
3. If the input is a ticket prefix, do NOT treat it as a ticket ID. Run `taskboard ticket list | grep <prefix>` to list that project's tickets. If exactly one ticket matches, use it; if several match, ask the user which ticket number they mean. NEVER use the bare prefix as a ticket ID, worktree name, or branch name.
4. `<ticket-id>` used for naming throughout this skill is the ticket ID in short form `<prefix>-<number>` (e.g. `KP-3`), resolved as follows:
   - Input is a ticket ID short form: `<ticket-id>` is the input verbatim.
   - Input is an internal ULID, or the ticket was resolved from a prefix: `<ticket-id>` is `<projectPrefix>-<number>` from the retrieved ticket record.
   - `<ticket-id>` is NEVER the bare ticket prefix value (`projectPrefix`, e.g. `KP`); that field is for lookup/grouping only.

## Worktree gate (MUST pass before any implementation)

Run both checks; every later step of this skill runs only after both succeed:

1. You are inside a linked worktree, not the main checkout:

   ```bash
   test "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)"
   ```

2. You are on the ticket branch `<ticket-id>` (the ticket ID short form, e.g. `KP-3`), not the default branch and not the bare ticket prefix:

   ```bash
   test "$(git branch --show-current)" = "<ticket-id>"
   ```

If a check fails, fix it before continuing:

- Check 1 fails (you are in the main checkout): create the worktree under `${HOME}/projects/worktrees/<repo-name>/<ticket-id>`, then `cd` into it and re-run the gate.
  - Inside Herdr (`HERDR_ENV=1`): ensure `${HOME}/projects/worktrees/<repo-name>` exists (`mkdir -p "${HOME}/projects/worktrees/<repo-name>"`), then `herdr worktree create --branch <ticket-id> --label <ticket-id> --path "${HOME}/projects/worktrees/<repo-name>/<ticket-id>" --no-focus`, then `cd` into the created worktree directory reported in the JSON result (`result.worktrees[].path`).
  - Outside Herdr: resolve the default branch with `git symbolic-ref refs/remotes/origin/HEAD` (strip the remote prefix; fall back to `main` only after confirming with the user), ensure `${HOME}/projects/worktrees/<repo-name>` exists (`mkdir -p "${HOME}/projects/worktrees/<repo-name>"`), then `git fetch origin && git worktree add "${HOME}/projects/worktrees/<repo-name>/<ticket-id>" -b <ticket-id> <default-branch> && cd "${HOME}/projects/worktrees/<repo-name>/<ticket-id>"`.
- Check 2 fails but check 1 passes: locate the worktree for branch `<ticket-id>` with `git worktree list --porcelain` (or the `wt-dir` helper from `tb-issue-finish/scripts/herdr-workspace.sh`), `cd` into it, and re-run the gate. If no such worktree exists, treat it as check 1 failing.
- Wrong-name mismatch: IF an existing worktree or branch for this ticket was created under the bare ticket prefix (e.g. `KP` instead of `KP-3`), do NOT reuse, rename, or delete it silently — report the mismatch to the user and stop for their decision.
- Worktree creation fails: stop and report the error to the user. NEVER continue implementing in the main checkout as a fallback.

## Instructions

1. Resolve the input to a ticket ID (short form `<ticket-id>` plus the internal 26-char ULID):
   - Input is a ticket ID short form: run `taskboard ticket list | grep <ticket-id>` to get the internal ULID.
   - Input is an internal ULID: run `taskboard ticket list | grep <ulid>` to get the short form `<ticket-id>`.
   - Input is a ticket prefix: follow Input rule 3 — list the project's tickets, use the single match, or ask the user which ticket they mean.
   You should not ask the user for the ticket ID if the user has already provided a ticket ID or an unambiguous ticket prefix.
2. Use tool `taskboard_get_ticket` to retrieve the ticket details with the resolved ticket ID (the internal ULID). If the ticket is not found, return a message indicating that the ticket does not exist.
3. If the ticket status is todo, use tool `taskboard_update_ticket` to change the status to in_progress and team to agent. Otherwise, if the ticket status is in_progress, continue to the next step. If the ticket status is done, return a message indicating that the issue has already been resolved.
4. If the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the user asked to start the ticket from inside Herdr AND the Worktree gate does NOT pass yet (i.e., you are not already the agent running inside the ticket's worktree), run the Herdr automation workflow below. If the gate already passes, you ARE the spawned agent: skip the automation and continue with step 5.
5. Run the Worktree gate for ticket branch `<ticket-id>` (see above). This step MUST pass before any implementation step. All remaining steps run inside the worktree directory.
6. Important: MUST use skill `spec-driven-development` to create a solution for the issue.
7. Important rule: The output of phase 1 of the `spec-driven-development` skill (`Requirements Gathering`) MUST be updated back to the taskboard ticket description.
8. Additional steps as needed by the `spec-driven-development` skill to complete the solution.
9. When the implementation finishes, apply Rules 3 and 4: do not move the ticket to `done`; stage exactly the ticket-relevant changes without committing. First confirm with `git rev-parse --show-toplevel` that you are staging inside the ticket worktree, not the main checkout.

## Herdr automation workflow (only when `HERDR_ENV=1` and not already inside the ticket worktree)

Use this workflow to bootstrap the implementation environment automatically, replacing the manual steps (create worktree workspace → start pi agent → send the prompt).

1. Create the worktree workspace named by the ticket ID under `${HOME}/projects/worktrees/<repo-name>`, without stealing focus. For ticket KP-3 in repo `skills` this is literally `--branch KP-3 --label KP-3` — never `--branch KP`:

   ```bash
   mkdir -p "${HOME}/projects/worktrees/<repo-name>" && herdr worktree create --branch <ticket-id> --label <ticket-id> --path "${HOME}/projects/worktrees/<repo-name>/<ticket-id>" --no-focus
   ```

   Read the workspace ID and pane ID from the JSON result. On failure, report the error to the user and stop — do not start the agent, and do not implement the ticket yourself.
2. Start the pi coding agent in the worktree workspace's shell pane, running the same command you would run manually — `pi -a '/approval-mode act'` — expressed through herdr as:

   ```bash
   herdr agent start <agent-name> --kind pi --pane <pane-id> -- -a "/approval-mode act"
   ```

   The pane ID comes from step 1. Choose a unique agent name matching `[a-z][a-z0-9_-]{0,31}`. On failure, report the error and leave the workspace for manual inspection.
3. Deliver the ticket prompt to the agent so it starts working in the new session:

   ```bash
   herdr agent prompt <agent-name> "/skill:tb-issue-start <ticket-id>"
   ```

   Optionally pass `--wait` to wait only until the agent settles after its first turn — never wait for the whole implementation.
4. Report the created workspace ID, pane ID, and agent name back to the user, then return control to them. Do not focus the workspace; the user will interact with the agent as needed and run skill `tb-issue-finish <ticket-id>` after reviewing the result.
