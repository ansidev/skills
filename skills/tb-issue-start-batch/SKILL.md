---
description: Use this skill when the user wants to implement multiple taskboard tickets in one batch — e.g. "implement these tickets", "run all pending tickets", "batch implement KP-1 KP-2 KP-3", or any request mentioning implementing tickets according to a dependency graph. It computes which tickets are ready, runs independent tickets in parallel through skill tb-issue-start, and tracks progress in a resumable queue file.
license: MIT
name: tb-issue-start-batch
---
# tb-issue-start-batch

## When to use

Use this skill when the user gives you two or more taskboard tickets to implement (or asks to implement all open tickets of a project) and wants them executed as one batch: dependencies respected, independent tickets run in parallel, and progress resumable if the session is interrupted. This skill is the batch orchestrator: it never implements a ticket itself — every ticket is implemented by a child agent running skill `tb-issue-start` inside that ticket's worktree.

## Rules

1. Use the MCP tools of the MCP called `taskboard`. Use skill `tb-cli` to fetch information not available via MCP.
2. Use skill `herdr` for all Herdr interactions. Before any `herdr` command, verify this agent runs inside Herdr with `test "${HERDR_ENV:-}" = 1`; if the check fails, use the non-Herdr spawning mode below instead.
3. Worktree enforcement (HARD RULE): all implementation happens inside ticket worktrees created by this orchestrator and worked on by child agents via `tb-issue-start`. NEVER read, edit, stage, or implement anything in the main checkout or on `main`/`develop`.
4. Base branch (HARD RULE): a top-level ticket's worktree branch is created off the batch base branch (see Base branch resolution). A non-top-level ticket's worktree branch MUST be created off its direct parent's ticket branch `<parent-ticket-id>` — never off the base branch, a grandparent's branch, or another sibling's branch.
5. Never set a taskboard ticket status to `done`. Closing a ticket is reserved for skill `tb-issue-finish`, which the user runs explicitly after manual review. During the batch, tickets stay `in_progress` on the taskboard; the queue file is the only place this skill marks `done`.
6. Queue file discipline: the queue file is the single source of truth for batch progress. The parent agent is its only writer; child agents never touch it. Update it through `scripts/tasks.py` (from this skill's directory) immediately after every state change — never keep progress only in memory. Never stage or commit the queue file, and run the script from the main repository checkout so its default path `<repo-root>/.agents/tb-batch/tasks.json` resolves there.
7. When committing a finished ticket, commit only what the child agent staged (`git commit`, no `-a`); never stage unrelated files, temp artifacts, or the queue file.
8. Never wait for the whole implementation inside a single `herdr agent prompt --wait`; that only waits for the agent's first settled turn. Completion is detected by polling, as described under Monitoring.

## Input

1. Input is one or more taskboard ticket IDs and/or ticket prefixes, optionally with an explicit dependency graph. Ticket IDs and prefixes are different strings and MUST NOT be conflated:
   - **Ticket prefix**: the project prefix, e.g. `KP` (the `projectPrefix` field on the ticket record). Shared by every ticket of the project; for lookup/grouping only.
   - **Ticket ID**: the per-ticket identifier in short form `<prefix>-<number>`, e.g. `KP-3` (what `taskboard ticket list` shows in brackets).
2. Recognise each input token by its shape:
   - Matches `^[A-Z]+-[0-9]+$` (e.g. `KP-3`): a ticket ID (short form).
   - Is a 26-character uppercase alphanumeric string (ULID): a ticket ID (internal form).
   - Is a bare alphabetic string without a `-<number>` part (e.g. `KP`): a ticket prefix. If the user means "all open tickets of this project", run `taskboard ticket list | grep <prefix>`, take tickets with status `todo`/`in_progress`, and confirm the resulting ticket list with the user before starting the batch. If several tickets match and the intent is ambiguous, ask the user which ones they mean.
3. Resolve every input to ticket IDs in short form `<prefix>-<number>` (e.g. `KP-3`); from a ULID, take `<projectPrefix>-<number>` from the ticket record. `<ticket-id>` is NEVER the bare prefix.

## Queue file

One JSON file holds every batch, keyed by a batch id derived from the batch's ticket ids, so re-running the same prompt finds and resumes the same batch:

- Path: `<repo-root>/.agents/tb-batch/tasks.json` (relative to the main checkout).
- Manage it only through `python3 "<skill-dir>/scripts/tasks.py" ...` where `<skill-dir>` is the directory containing this SKILL.md. Commands:
  - `init --ticket <id> ... [--dep <child>=<parent> ...]` — create the batch, or merge into an existing one (resume: statuses and progress are preserved, the dependency graph is refreshed). Fails on a dependency cycle. Prints the batch (including the derived `batch_id`) as JSON.
  - `show --batch-id <id> [--status <s>]` — print tickets as JSON.
  - `ready --batch-id <id>` — print startable tickets (status `pending`, all dependencies `done`) as JSON. Dependencies outside the batch count as satisfied (the workflow verifies them at graph-build time).
  - `set --batch-id <id> --ticket <id> --status <pending|in_progress|done|failed> [--base-branch <b>] [--worktree <path>] [--agent <name>] [--commit <sha>] [--note <text>] [--field <key>=<value>]` — update one ticket.

Ticket entry shape (written by the script):

```json
{
  "id": "KP-3",
  "depends_on": ["KP-2"],
  "status": "pending",
  "base_branch": "KP-2",
  "branch": "KP-3",
  "worktree": "/Users/<you>/projects/worktrees/<repo-name>/KP-3",
  "agent": "tb-kp-3",
  "commit": null,
  "note": null,
  "updated_at": "2026-09-07T04:45:58Z"
}
```

## Workflow

### Phase 1 — Collect tickets and build the dependency graph

1. Resolve the user input to ticket IDs (Input rules above) and fetch every ticket with `taskboard_get_ticket`. A missing ticket is an error: report it and stop.
2. Determine dependencies, in priority order:
   1. Ticket records that expose dependency information — use it.
   2. An explicit graph the user supplied in the request — use it.
   3. Otherwise ask the user for the graph before proceeding.
3. Dependencies pointing at tickets outside the batch: check their taskboard status. If `done`, treat them as satisfied. If not done, ask the user either to add them to the batch or to abort; never start a ticket whose external dependency is unfinished.
4. Run `init` with all tickets and `--dep child=parent` edges. It writes the queue file, fails on cycles (report the printed cycle path and stop), and prints the `batch_id` used by every later call.

### Phase 2 — Recovery pass (also the resume path)

Read the batch with `show`. For every ticket NOT `pending`:

- `done`: skip — nothing to do. This is how a re-run of the same prompt skips completed tickets.
- `in_progress`:
  - A live child agent is still working on it (Herdr: `herdr agent get <agent-name>` reports `working`; non-Herdr: the subagent session is still running) → keep it and continue monitoring; do not respawn.
  - No live agent, but the worktree contains staged or uncommitted changes → spawn a fresh child agent for the same ticket (see Spawning) with the prompt `/skill:tb-issue-start <ticket-id>`; `tb-issue-start` re-enters the existing worktree through its worktree gate and continues.
  - No live agent, worktree clean, but the branch has a commit this batch made (the queue file was not updated before an interruption) → verify the commit exists, then `set --status done --commit <sha>`.
  - No live agent, worktree clean, no batch commit → `set --status pending` (the worktree is reused as-is).
- `failed`: leave as `failed`; report it in Phase 4 and ask the user whether to retry. Its dependents stay blocked.

### Phase 3 — Main loop

Repeat until no ticket is `pending`, `in_progress`, or `failed`:

1. Run `ready`. For every ticket in the output (all of them can start in parallel; if the user specified a concurrency cap, start only up to the cap):
   1. Resolve its base branch (Base branch resolution below) and record it: `set --ticket <id> --base-branch <branch>`.
   2. Create its worktree BEFORE spawning the child, so `tb-issue-start`'s worktree gate passes unchanged. Run from the main checkout:

      ```bash
      mkdir -p "${HOME}/projects/worktrees/<repo-name>"
      git worktree add "${HOME}/projects/worktrees/<repo-name>/<ticket-id>" -b <ticket-id> <base-branch>
      ```

      If the branch or worktree already exists (resume), reuse it after verifying the worktree is on branch `<ticket-id>`; do not recreate or delete it. For a ticket with several dependencies, `<base-branch>` is the FIRST dependency's branch; after creating the worktree, merge every other dependency's branch into it (`git -C <worktree> merge <dep-branch>`). If that merge conflicts, stop, report, and mark the ticket `failed` — do not resolve conflicts yourself.
   3. Spawn a child agent in the worktree (Spawning below) and record it: `set --ticket <id> --status in_progress --worktree <path> --agent <name>`.
2. Monitor all running children (Monitoring below). When a child finishes, complete its ticket (Completion below) — this is what unblocks its dependents.
3. Loop back to step 1. Newly ready tickets start while others are still running.

### Phase 4 — Final report

When the loop ends, print a summary table — ticket ID, title, status, branch, commit (short sha) — and:

- For every `done` ticket: remind the user to review its branch/worktree and run `/tb-issue-finish <ticket-id>` AFTER manual review, in parent-first (topological) order, so each ticket merges into the base branch before its dependents are finished. All tickets remain `in_progress` on the taskboard until the user does this.
- For every `failed` ticket: its note, and the list of dependents it blocked.
- The queue file path, so the user can re-run the same prompt later to resume.

## Base branch resolution

For a top-level ticket (no dependencies in the batch graph):

```bash
# 1. Git flow: enabled when gitflow config exists or a remote develop branch exists
git config --get gitflow.branch.develop
git ls-remote --heads origin develop
```

- If the gitflow config returns a value → base branch is that value (usually `develop`).
- Else if a remote `develop` branch exists → base branch is `develop`.
- Else resolve the default branch with `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/` prefix; fall back to `main` only after confirming with the user.

For a non-top-level ticket: base branch is `<parent-ticket-id>` — the ticket branch of its first (primary) dependency, which must have status `done` in the queue file before this ticket becomes ready (`ready` guarantees this). Run `git fetch origin` before creating the first top-level worktrees.

## Spawning child agents

Name each agent `tb-<ticket-id in lowercase>` (e.g. `tb-kp-3`); it matches the Herdr name pattern `[a-z][a-z0-9_-]{0,31}` and is unique per batch.

Inside Herdr (`HERDR_ENV=1`) — the worktree already exists, so create a workspace on it (do NOT use `herdr worktree create`, which would branch off the wrong base):

```bash
herdr workspace create --cwd "${HOME}/projects/worktrees/<repo-name>/<ticket-id>" --no-focus
herdr agent start <agent-name> --kind pi --pane <pane-id> -- -a "/approval-mode act"
herdr agent prompt <agent-name> "/skill:tb-issue-start <ticket-id>" --wait --timeout 120000
```

The pane ID comes from the workspace creation JSON (`.result.root_pane.pane_id`). Parse all IDs from JSON responses, never from examples. On any failure, report the error, mark the ticket `failed`, and continue with other tickets.

Outside Herdr — spawn a subagent with the platform's subagent mechanism, in the background so several run in parallel, with a prompt of the form: "Work in the directory `<worktree path>` (cd there first) and invoke skill `tb-issue-start` for ticket `<ticket-id>`. Follow every rule of that skill. Report a concise result: what you implemented, test results, and the list of files you staged." The subagent's completion notification is how the parent learns the child finished.

## Monitoring

Poll the running children in a loop; between polls, `sleep 60` and re-check — never busy-loop:

- Herdr: `herdr agent get <agent-name>` for each running child.
  - `done`/`idle`: the child settled → read its final output (`herdr agent read <agent-name> --source recent-unwrapped --lines 120`) and complete the ticket (Completion below).
  - `blocked`: the child hit an approval/question UI → inspect with `herdr agent read`. Answer only simple factual questions via `herdr agent prompt`; anything else — report to the user and leave the ticket `in_progress` while the rest of the batch continues.
  - `working`: keep waiting. `unknown`: read the output and judge from it.
- Non-Herdr: wait for each subagent's completion notification; on completion, read its result and complete the ticket.

## Completion (per finished ticket)

Run from the main checkout, targeting the ticket worktree:

1. Verify the work: `git -C <worktree> status --porcelain` should show the staged, ticket-relevant changes, and the child's final output should report success and passing checks. If the child reported failure or left a mess, mark the ticket `failed` with `--note` describing why, and continue the batch.
2. Commit exactly what the child staged:

   ```bash
   git -C <worktree> commit -m "<type>(<ticket-id>): <ticket title>"
   ```

   Infer `<type>` from the change (feat, fix, refactor, docs, test, chore, ...). Never `commit -a`, never stage extra files. If nothing is staged and the child still reported success (e.g. docs-only or already-committed work), check `git -C <worktree> log` and proceed without a new commit.
3. Record it: `set --ticket <id> --status done --commit <short sha>`. The taskboard status stays `in_progress` (Rule 5). Committing on the ticket branch is what makes the ticket's dependents startable — their worktrees branch off this branch.
