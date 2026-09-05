# Requirements: tb-issue-herdr-automation (AK-2)

Update the `tb-issue-start` skill to support full automation when the coding agent runs
inside Herdr, fix its completion semantics (never auto-done, auto-stage changes), and add
a new `tb-issue-finish` skill for the user-driven finish workflow.

## Glossary

- **Herdr**: terminal multiplexer exposing the `herdr` CLI; the coding agent may run inside a Herdr-managed pane.
- **Ticket prefix**: short ticket identifier, e.g. `AK-2` (length < 26); a **ticket ID** is the 26-char ULID.
- **Worktree workspace**: a Herdr workspace backed by a git worktree created via `herdr worktree create`.
- **Taskboard**: local ticket tracker exposed via MCP (`taskboard_*` tools) and the `taskboard` CLI.

## Requirements

### Requirement 1: Herdr environment detection

**User Story:** As a coding agent running `tb-issue-start`, I want to detect whether I am running inside Herdr, so that I can choose the automated workflow instead of the manual one.

#### Acceptance Criteria

1. WHEN `tb-issue-start` starts, THE skill SHALL check `test "${HERDR_ENV:-}" = 1` to determine whether it runs inside Herdr.
2. IF `HERDR_ENV` is `1`, THEN `tb-issue-start` SHALL use the Herdr automation workflow (Requirement 2).
3. IF `HERDR_ENV` is not `1`, THEN `tb-issue-start` SHALL keep its existing (manual) behavior unchanged.

### Requirement 2: Automated worktree + agent bootstrap inside Herdr

**User Story:** As a user inside Herdr, I want the agent to create the worktree workspace and start a `pi` agent session automatically, so that I no longer perform the manual worktree/agent bootstrap steps.

#### Acceptance Criteria

1. WHEN the automation workflow runs with ticket prefix `<prefix>`, THEN the skill SHALL run `herdr worktree create` with the branch/label derived from `<prefix>` and SHALL NOT focus the new workspace (no `--focus`).
2. WHEN the worktree workspace exists, THEN the skill SHALL start a `pi` coding agent (`pi -a '/approval-mode act'`) in a pane of that workspace.
3. WHEN the `pi` agent is started, THEN the skill SHALL deliver the prompt `/skill:tb-issue-start <prefix>` to it and NOT wait synchronously for the full implementation to finish.

### Requirement 3: No automatic ticket completion

**User Story:** As a ticket owner, I want the ticket to be moved to done only after my confirmation, so that the agent never closes a ticket on its own.

#### Acceptance Criteria

1. WHEN the implementation work finishes, THEN the agent SHALL NOT change the ticket status to `done` at any point of the `tb-issue-start` workflow.
2. IF the ticket status needs to change to `done`, THEN this SHALL happen only through the `tb-issue-finish` skill (Requirement 5), which the user runs explicitly.

### Requirement 4: Automatic staging of relevant changes

**User Story:** As a user, I want the agent to stage the changes it made, so that I can review a clean, relevant diff without unrelated noise and without premature commits.

#### Acceptance Criteria

1. WHEN the agent finishes making changes relevant to the ticket, THEN it SHALL `git add` exactly the files it created or modified for the ticket.
2. WHEN staging changes, THEN the agent SHALL NOT commit or push anything.
3. IF a file change is unrelated to the ticket (or is incidental scratch/temp output), THEN the agent SHALL NOT stage it.
4. WHEN staging completes, THEN `git status` SHALL show staged ticket-relevant changes and no committed changes made by the agent.

### Requirement 5: New skill `tb-issue-finish`

**User Story:** As a user, I want a `tb-issue-finish` skill that commits, rebases, and merges the reviewed work and closes out the ticket, so that finishing a ticket is a single explicit step after my manual review.

#### Acceptance Criteria

1. WHEN the user explicitly invokes `tb-issue-finish` with a ticket prefix/ID, THEN the skill SHALL commit the currently staged changes using a Conventional Commit message whose optional scope is the ticket prefix (format `<type>(<prefix>): <description>`, e.g. `feat(AK-2): update tb-issue-start skill`).
2. WHEN committing, THEN the skill SHALL resolve the base branch properly (default `main`) and rebase the working branch onto it.
3. IF a git conflict occurs during the rebase, THEN the skill SHALL stop processing immediately and ask the user to resolve the conflict manually.
4. IF the rebase succeeds, THEN the skill SHALL merge the working branch back into the base branch.
5. WHEN the merge succeeds, THEN the skill SHALL use the `herdr` skill to close the worktree workspace and clean up the worktree (including branch deletion).
6. WHEN the worktree is cleaned up, THEN the skill SHALL use the `add-knowledge` skill to record knowledge related to the ticket in the OpenKnowledge base (via the `kb-okf` MCP).
7. WHEN all prior steps succeed, THEN the skill SHALL update the taskboard ticket status to `done` via the `taskboard` MCP tools (falling back to the `tb-cli`/`taskboard` CLI if MCP is unavailable).
8. IF any step before ticket closure fails, THEN the skill SHALL stop, report the failure, and leave the ticket status unchanged.

### Requirement 6: Compatibility

**User Story:** As a skill maintainer, I want the new behavior layered on the existing skills, so that non-Herdr usage and existing conventions keep working.

#### Acceptance Criteria

1. WHEN `tb-issue-start` is updated, THEN it SHALL preserve the existing input contract (ticket ID vs prefix detection, `taskboard` MCP + `tb-cli` rules, spec-driven-development handoff).
2. WHEN `tb-issue-finish` is created, THEN it SHALL live under `skills/tb-issue-finish/SKILL.md` with the same frontmatter conventions (name, description, license) as existing skills.

4. IF the worktree creation or agent start fails, THEN the skill SHALL report the failure to the user and SHALL NOT continue to the prompt-delivery step.
5. WHEN the skill invokes any `herdr` command, THEN it SHALL follow the `herdr` skill rules (verify `HERDR_ENV`, parse IDs from JSON responses, use `--no-focus`/`--current` for background work).