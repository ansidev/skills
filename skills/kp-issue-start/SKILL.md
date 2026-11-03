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
6. Before any host lifecycle operation, invoke `bash <skill-directory>/lib/host-runtime <operation> ...` and inspect its normalized JSON envelope. The adapter is vendored inside this skill at `lib/` so the installed skill directory is self-contained; if it is missing, stop and report the missing adapter instead of improvising with `herdr`/`hc` commands directly. If the adapter reports `runtime: "unknown"`, stop and report the detection error; never fall back to another host's command path. `herdr-tui` uses `herdr`; `herdr-desktop` uses `herdr-app` for window-side commands and `hc` for terminal/agent operations; `outside` performs no host commands.
7. Parse workspace/pane/terminal IDs only from the runtime adapter's structured result; never derive them from examples or sidebar ordering. Use non-focusing/background operations where the selected adapter supports them.
8. Worktree enforcement (HARD RULE): ALL implementation MUST happen inside a git worktree on a branch named `<issue-key>` created off the default branch. NEVER read, edit, stage, or run any implementation step in the main repository checkout or on `main`/`master`. This applies even when `HERDR_ENV` is unset, when the user says "just do it here", or when worktree creation fails — in those cases you stop and report instead of falling back to the main checkout. This rule exists so multiple agents can work on issues in parallel; violating it breaks every other in-flight issue.
9. Before the first implementation step, and again after any `cd` or checkout, verify Rule 7 with the Worktree gate below. The gate is a stop condition, not a suggestion.
10. Naming (HARD RULE): the worktree folder name, git branch name, and herdr workspace label MUST all be exactly the issue key `<issue-key>` (e.g. `KP-3`). NEVER use the bare project prefix (e.g. `KP`) as the worktree, branch, or label name; the project prefix drops the issue number and collides across issues of the same project.
11. Completion enforcement (HARD RULE): This skill MUST NOT return until implementation is complete, validation is run, and the issue status is changed to `in-review`. Stopping after posting a requirements comment, after Phase 1 of spec-driven-development, or before actual implementation is a violation. The skill drives the FULL workflow: assign → worktree gate → skill selection → spec-driven-development (all 3 phases) → implementation → validation → commit → status update.
12. Kanpal error handling: When kanpal tools return validation errors (e.g., "assign the issue to someone before this transition"), diagnose the specific constraint, address it (e.g., assign before status transition), then retry the original operation. Do not repeatedly retry the same failing operation without addressing the root cause.

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
      - Invoke `bash <skill-directory>/lib/host-runtime detect`; if `unknown`, stop and report.
      - If `herdr-tui` or `herdr-desktop`: run `bash <skill-directory>/lib/host-runtime worktree-create --issue <issue-key> --base <base-branch>`, then `cd` into `worktree_path` from the envelope.
      - If `outside`: resolve the default branch with `git symbolic-ref refs/remotes/origin/HEAD` (strip the remote prefix; fall back to `main` only after confirming with the user), `git fetch origin`, then run `bash <skill-directory>/lib/host-runtime worktree-create --issue <issue-key> --base <default-branch>` and `cd` into `worktree_path` from the envelope. When worktrunk (`wt`) is installed the adapter creates the worktree through `wt switch --create` (honoring its path template); otherwise it falls back to plain `git worktree add`.
- Check 2 fails but check 1 passes: locate the worktree for branch `<issue-key>` with `bash <skill-directory>/lib/host-runtime worktree-lookup --issue <issue-key>` or `git worktree list --porcelain`, `cd` into it, and re-run the gate. If no such worktree exists, treat it as check 1 failing.
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
4. Load the complete instructions of EVERY applicable skill before doing the work; load more later when new requirements or details make them relevant.
5. Follow all mandatory skills. If several apply, combine them; resolve conflicts using project rules, then explicit user requirements.
6. Prefer the smallest sufficient set. Do not load unrelated skills, and never claim a skill was applied unless you read and followed its instructions.
7. If the task is ambiguous, inspect the codebase first; ask for clarification only when necessary.
8. Before finishing, run the validation procedures required by the selected skills.

**MANDATORY**: You MUST complete the skill selection policy BEFORE calling `spec-driven-development`. Do not skip this step or assume no other skills apply.

## Instructions

1. Input is a issue key.
2. Use tool `kanpal_get_issue` to retrieve the issue details with the resolved issue key. If the issue is not found, return a message indicating that the issue does not exist.
3. Self-assign if unassigned (MUST come before status transition): if the issue (from `kanpal_get_issue`) has no assignee, assign it to yourself with `kanpal_assign_issue` (`{"id":"<issue-id>","user_id":"<your-user-id>"}`). Resolve `<your-user-id>` by calling `kanpal_get_me` (no parameters), which returns the connected agent's record; use its `id` field (an agent's id is also its user id). NEVER ask the user who the assignee is. If the issue is already assigned (to anyone, including you), leave the assignee unchanged. If `kanpal_get_me` fails or the assignment is refused (archived agent, outside the project's team), report it to the user and continue without reassigning anyone else.
4. If the issue status is `todo`, use tool `kanpal_update_issue` to change the status to `in-progress` and team to `agent`. The kanpal system requires the issue to be assigned (step 3) before this transition can succeed. Otherwise, if the issue status is `in-progress`, continue to the next step. If the issue status is done, return a message indicating that the issue has already been resolved.
5. If the Worktree gate does NOT pass yet (i.e., you are NOT already the agent running inside the issue's worktree) AND the host-runtime adapter reports a managed host that supports agent launch (`herdr-tui` or `herdr-desktop`, not `outside` or `unknown`), run the Herdr automation workflow below. The runtime is determined by running `bash <skill-directory>/lib/host-runtime detect`; do NOT gate this on the `HERDR_ENV` environment variable — desktop hosts expose the adapter even when `HERDR_ENV` is unset. If the gate already passes, you ARE the spawned agent: skip the automation and continue with step 6. If the runtime is `outside` or `unknown`, do NOT attempt to launch a separate agent; proceed inline via the Worktree gate.
6. Run the Worktree gate for issue branch `<issue-key>` (see above). This step MUST pass before any implementation step. All remaining steps run inside the worktree directory.
7. Important: Apply the Skill selection policy above to pick the skills for this issue, then MUST use skill `spec-driven-development` (always-on) alongside them to create a solution for the issue.

   **CRITICAL**: Using `spec-driven-development` means FULLY executing all three phases:
   - Phase 1: Requirements Gathering (user stories, acceptance criteria in EARS format)
   - Phase 2: Design Documentation (architecture, components, data models, error handling)
   - Phase 3: Task Planning (break design into actionable implementation tasks)

   Do NOT skip phases, do NOT substitute manual notes for the skill's systematic process, and do NOT stop after posting a requirements comment. Continue through all phases and implement the tasks.

8. Important rule: The output of phase 1 of the `spec-driven-development` skill (`Requirements Gathering`) MUST be updated back to the respective kanpal issue comments alongside the skill behaviour. This comment is PART of phase 1, not a replacement for the full skill execution.

9. Execute the complete `spec-driven-development` workflow:
   - Phase 1: Gather requirements using the skill's EARS format process
   - Post Phase 1 output to kanpal issue comments
   - Phase 2: Create design documentation per the skill's structure
   - Phase 3: Break down into implementation tasks per the skill's task planning
   - Implement the tasks in sequence, following task dependencies
   - Apply any additional task-specific skills selected in step 7

10. When the implementation finishes, run the validation procedures required by the selected skills, then change the issue status to `in-review`; commit exactly the issue-relevant changes without pushing. First confirm with `git rev-parse --show-toplevel` that you are committing inside the issue worktree, not the main checkout.

## Managed host automation workflow (only when NOT already inside the issue worktree and a managed host is available)

Use this workflow to bootstrap the implementation environment automatically, replacing the manual steps (create worktree workspace → start pi agent → send the prompt).

1. Create the worktree workspace named by the issue ID, without stealing focus. For issue KP-3 in repo `skills` this is literally `--branch KP-3 --label KP-3` — never `--branch KP`. The adapter uses `wt switch --create` (worktrunk, honoring its path template) when `wt` is installed, `herdr worktree create` under herdr-tui, and plain `git worktree add` otherwise:

   ```bash
   bash <skill-directory>/lib/host-runtime worktree-create --issue <issue-key> --base <base-branch>
   ```

   Read the workspace ID and pane ID from the JSON result. On failure, report the error to the user and stop — do not start the agent, and do not implement the issue yourself.
2. Start the pi coding agent in the worktree workspace's shell pane, running the same command you would run manually — `pi -a '/approval-mode act'` — expressed through herdr as:

   ```bash
   bash <skill-directory>/lib/host-runtime agent-start --issue <issue-key> --args "pi -a '/approval-mode act'"
   ```

   The pane ID comes from step 1. Choose a unique agent name matching `[a-z][a-z0-9_-]{0,31}`. On failure, report the error and leave the workspace for manual inspection.
3. Deliver the issue prompt to the agent so it starts working in the new session:

   ```bash
   bash <skill-directory>/lib/host-runtime agent-prompt --issue <issue-key> --text "/skill:kp-issue-start <issue-key>"
   ```

   Optionally pass `--wait` to wait only until the agent settles after its first turn — never wait for the whole implementation.
4. Report the created workspace ID, pane ID, and agent name back to the user, then return control to them. Do not focus the workspace; the user will interact with the agent as needed and run skill `kp-issue-finish <issue-key>` after reviewing the result.
