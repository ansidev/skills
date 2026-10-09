---
name: kp-issue-start
description: Use this skill to start working on the solution for the relevant kanpal issue. When the user asks to fix, correct, or start an issue in the kanpal, this skill will be activated.
license: MIT
---

# kp-issue-start

## When to use

Use this skill when the user asks to fix, correct, or resolve an issue in the kanpal. This skill will be activated to start working on the solution for the relevant kanpal issue.

## Rules

1. MUST use available tools from `kanpal` MCP.
2. MUST call tool `kanpal_get_issue` with parameter `{"key": "<issue-key>"}` to get issue ID from field `id`.
3. MUST call tool `kanpal_update_issue` with parameter `{"id":"<issue-id>"}`.
4. NEVER set a issue status to `done` in this skill. Closing a issue is reserved for skill `kp-issue-finish`, which the user runs explicitly after manual review.
5. When the implementation work finishes, stage exactly the issue-relevant files with `git add <files>`; then create local commit. NEVER push, and NEVER stage unrelated files, temp artifacts, or scratch output.
6. Before any `herdr` command, verify this agent runs inside Herdr with `test "${HERDR_ENV:-}" = 1`; if the check fails, say you are not running inside Herdr and do not issue herdr commands.
7. Parse workspace/pane/agent IDs from herdr JSON responses; never derive them from examples or sidebar order. Use `--no-focus`/`--current` for background work.
8. Worktree enforcement (HARD RULE): ALL implementation MUST happen inside a git worktree on a branch named `<issue-key>` created off the default branch. NEVER read, edit, stage, or run any implementation step in the main repository checkout or on `main`/`master`. This applies even when `HERDR_ENV` is unset, when the user says "just do it here", or when worktree creation fails — in those cases you stop and report instead of falling back to the main checkout. This rule exists so multiple agents can work on issues in parallel; violating it breaks every other in-flight issue.
9. Before the first implementation step, and again after any `cd` or checkout, verify Rule 7 with the Worktree gate below. The gate is a stop condition, not a suggestion.
10. Naming (HARD RULE): the worktree folder name, git branch name, and herdr workspace label MUST all be exactly the issue key `<issue-key>` (e.g. `KP-3`). NEVER use the bare project prefix (e.g. `KP`) as the worktree, branch, or label name; the project prefix drops the issue number and collides across issues of the same project.

## Worktree gate (MUST pass before any implementation)

Run both checks; every later step of this skill runs only after both succeed:

1. You are inside a linked worktree, not the main checkout:

   ```bash
   test "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)"
   ```

2. You are on the issue branch `<issue-key>` (e.g. `KP-3`), not the default branch and not the bare issue key:

   ```bash
   test "$(git branch --show-current)" = "<issue-key>"
   ```

If a check fails, fix it before continuing:

- Check 1 fails (you are in the main checkout): create the worktree under `${HOME}/projects/worktrees/<repo-name>/<issue-key>`, then `cd` into it and re-run the gate.
   - Inside Herdr (`HERDR_ENV=1`): run `bash <skill-directory>/scripts/script.sh wt-switch -c -b <base-branch> -f false -t <issue-key>`, then `cd "${HOME}/projects/worktrees/<repo-name>/<issue-key>"`. Set `<base-branch>` to the resolved default branch.
  - Outside Herdr: resolve the default branch with `git symbolic-ref refs/remotes/origin/HEAD` (strip the remote prefix; fall back to `main` only after confirming with the user), ensure `${HOME}/projects/worktrees/<repo-name>` exists (`mkdir -p "${HOME}/projects/worktrees/<repo-name>"`), then `git fetch origin && git worktree add "${HOME}/projects/worktrees/<repo-name>/<issue-key>" -b <issue-key> <default-branch> && cd "${HOME}/projects/worktrees/<repo-name>/<issue-key>"`.
- Check 2 fails but check 1 passes: locate the worktree for branch `<issue-key>` with `git worktree list --porcelain` (or the `wt-dir` helper from `kp-issue-finish/scripts/herdr-workspace.sh`), `cd` into it, and re-run the gate. If no such worktree exists, treat it as check 1 failing.
- Wrong-name mismatch: IF an existing worktree or branch for this issue was created under the bare issue key (e.g. `KP` instead of `KP-3`), do NOT reuse, rename, or delete it silently — report the mismatch to the user and stop for their decision.
- Worktree creation fails: stop and report the error to the user. NEVER continue implementing in the main checkout as a fallback.

## Skill selection policy

Workflow: task → classify → resolve skills → execute → verify → report. Agent-agnostic: use whatever skill discovery and loading mechanism your agent provides.

- Always-on: project rules (e.g. `AGENTS.md`), coding conventions, safety rules, and `spec-driven-development`.
- Task-specific: skills matching the affected area (frontend, backend, database, docs, ...).
- Validation: skills for the checks the task needs (tests, linting, browser verification, ...).

Before implementing:

1. Understand the task, affected components, framework, and acceptance criteria.
2. Discover available skills from the global and project skill directories your agent is configured with.
3. Read each candidate skill's name and description to judge relevance.
4. Load the complete instructions of every applicable skill before doing the work; load more later when new requirements or details make them relevant.
5. Follow all mandatory skills. If several apply, combine them; resolve conflicts using project rules, then explicit user requirements.
6. Prefer the smallest sufficient set. Do not load unrelated skills, and never claim a skill was applied unless you read and followed its instructions.
7. If the task is ambiguous, inspect the codebase first; ask for clarification only when necessary.
8. Before finishing, run the validation procedures required by the selected skills.

## Instructions

1. Input is a issue key.
2. Use tool `kanpal_get_issue` to retrieve the issue details with the resolved issue key. If the issue is not found, return a message indicating that the issue does not exist.
3. If the issue status is `todo`, use tool `kanpal_update_issue` to change the status to `in-progress` and team to `agent`. Otherwise, if the issue status is `in-progress`, continue to the next step. If the issue status is done, return a message indicating that the issue has already been resolved.
4. If the Herdr check `test "${HERDR_ENV:-}" = 1` passes AND the user asked to start the issue from inside Herdr AND the Worktree gate does NOT pass yet (i.e., you are not already the agent running inside the issue's worktree), run the Herdr automation workflow below. If the gate already passes, you ARE the spawned agent: skip the automation and continue with step 5.
5. Run the Worktree gate for issue branch `<issue-key>` (see above). This step MUST pass before any implementation step. All remaining steps run inside the worktree directory.
6. Important: Apply the Skill selection policy above to pick the skills for this issue, then MUST use skill `spec-driven-development` (always-on) alongside them to create a solution for the issue.
7. Important rule: The output of phase 1 of the `spec-driven-development` skill (`Requirements Gathering`) MUST be updated back to the respective kanpal issue comments alongside the skill behaviour.
8. Additional steps as needed by the `spec-driven-development` skill to complete the solution.
9. When the implementation finishes, run the validation procedures required by the selected skills, then change the issue status to `in-review`; commit exactly the issue-relevant changes without pushing. First confirm with `git rev-parse --show-toplevel` that you are committing inside the issue worktree, not the main checkout.

## Herdr automation workflow (only when `HERDR_ENV=1` and not already inside the issue worktree)

Use this workflow to bootstrap the implementation environment automatically, replacing the manual steps (create worktree workspace → start pi agent → send the prompt).

1. Create the worktree workspace named by the issue ID under `${HOME}/projects/worktrees/<repo-name>`, without stealing focus. For issue KP-3 in repo `skills` this is literally `--branch KP-3 --label KP-3` — never `--branch KP`:

   ```bash
   mkdir -p "${HOME}/projects/worktrees/<repo-name>" && herdr worktree create --branch <issue-key> --label <issue-key> --path "${HOME}/projects/worktrees/<repo-name>/<issue-key>" --no-focus
   ```

   Read the workspace ID and pane ID from the JSON result. On failure, report the error to the user and stop — do not start the agent, and do not implement the issue yourself.
2. Start the pi coding agent in the worktree workspace's shell pane, running the same command you would run manually — `pi -a '/approval-mode act'` — expressed through herdr as:

   ```bash
   herdr agent start <agent-name> --kind pi --pane <pane-id> -- -a "/approval-mode act"
   ```

   The pane ID comes from step 1. Choose a unique agent name matching `[a-z][a-z0-9_-]{0,31}`. On failure, report the error and leave the workspace for manual inspection.
3. Deliver the issue prompt to the agent so it starts working in the new session:

   ```bash
   herdr agent prompt <agent-name> "/skill:kp-issue-start <issue-key>"
   ```

   Optionally pass `--wait` to wait only until the agent settles after its first turn — never wait for the whole implementation.
4. Report the created workspace ID, pane ID, and agent name back to the user, then return control to them. Do not focus the workspace; the user will interact with the agent as needed and run skill `kp-issue-finish <issue-key>` after reviewing the result.
