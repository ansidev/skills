---
name: ad-implement
description: Use to implement a fix for a known issue, or to implement a new feature.
license: MIT
---

## Input

- A markdown file describing the task, constraints, acceptance criteria, and relevant project context.
- If the task is ambiguous, unclear, or missing required context, stop and ask for clarification before implementation starts.

## Main Workflow

1. **Scope and plan check** - Confirm the task is bounded, the success criteria are explicit, and the work can be broken into independent sub-tasks when appropriate.
2. **dispatching-parallel-agents** - Activates with the plan. Dispatches fresh subagents per task in parallel when the work is independent; otherwise keep execution sequential. Each task is reviewed in two stages: spec compliance, then code quality.

## Subagent Workflow

1. **using-git-worktrees** - Activates before implementing a task. Each subagent creates an isolated worktree on a fresh branch for the task, sets up the required project environment, and confirms the baseline is clean before code changes begin.

2. **test-driven-development** - Activates during implementation. Enforces RED-GREEN-REFACTOR: write a failing test that captures the behavior, run it and confirm it fails, implement the minimal fix, run the targeted check and confirm it passes, then refactor if needed. Code written before the failing test is considered invalid and must be deleted or rewritten.

3. **requesting-code-review** - Activates between tasks or milestones. Reviews the delta against the plan and acceptance criteria, reports issues by severity, and blocks progress on critical findings. If evidence is missing, the reviewer must call for a verification step before continuing.

4. **finishing-a-development-branch** - Activates when the task is complete and review is cleared. Verifies the relevant tests/build checks still pass, presents the merge options (rebase then merge/PR/keep/discard), and cleans up the worktree.

**The agent checks for relevant skills before any task.** Mandatory workflows, not suggestions.

**Required gate:** no task continues past a review checkpoint or implementation milestone unless the relevant verification evidence exists and the required checks have passed.
