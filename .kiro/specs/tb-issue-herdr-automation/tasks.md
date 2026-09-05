# Implementation Plan: tb-issue-herdr-automation (AK-2)

## Overview

Sequential tasks following foundation-first ordering: update `tb-issue-start` first (it
defines the contract `tb-issue-finish` completes), then create `tb-issue-finish`, then
validate and close out. Each task maps to requirements in `requirements.md`.

## Tasks

- [ ] 1. Update `skills/tb-issue-start/SKILL.md` with Herdr automation and completion rules
  - [ ] 1.1 Add Herdr detection rule
    - Add a rule running `test "${HERDR_ENV:-}" = 1` before any herdr command; branch to the
      automation workflow only when it passes (Req 1.1–1.3)
    - _Requirements: 1.1, 1.2, 1.3, 6.1_
  - [ ] 1.2 Add the Herdr automation workflow section
    - Document the steps: resolve ticket (existing contract) → `herdr worktree create
      --branch <prefix> --label <prefix> --no-focus` → start `pi -a '/approval-mode act'`
      via `herdr agent start` in the worktree pane (syntax discovered via `herdr agent`) →
      deliver `/skill:tb-issue-start <prefix>` via `herdr agent prompt` → report IDs
    - Include the failure path: report and stop if worktree creation or agent start fails
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_
  - [ ] 1.3 Add "never auto-done" rule
    - Explicit rule: the agent must not set the ticket status to `done` anywhere in this
      skill; closing is reserved for `tb-issue-finish` on explicit user invocation
    - _Requirements: 3.1, 3.2_
  - [ ] 1.4 Add auto-staging rule
    - Explicit rule: stage exactly the ticket-relevant files with `git add`; never commit
      or push; never stage unrelated files or scratch output
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - [ ] 1.5 Validate updated `tb-issue-start` against a scratch ticket
    - Manual/agent rehearsal inside a Herdr test session; verify frontmatter stays valid,
      non-Herdr flow unchanged, all EARS criteria 1.x–4.x observable
    - _Requirements: 1.x, 2.x, 3.x, 4.x, 6.1_

- [ ] 2. Create `skills/tb-issue-finish/SKILL.md` — **extracted to ticket [AK-5] (`01M1R5BAW789EFV56M896652AJ`), tracked there; do not implement under AK-2**
  - [ ] 2.1 Write frontmatter and skill skeleton
    - `name: tb-issue-finish`, description triggering on explicit finish requests, `license: MIT`
    - _Requirements: 6.2_
  - [ ] 2.2 Write the ticket resolution and guard-rail steps
    - Prefix/ID input contract; require staged changes (`git status --porcelain`); stop if
      nothing staged
    - _Requirements: 5.1, 5.8_
  - [ ] 2.3 Write commit, rebase, and merge steps
    - Conventional Commit `<type>(<prefix>): <description>`; base-branch resolution; rebase
      with conflict stop-and-ask; merge back into base branch
    - _Requirements: 5.1, 5.2, 5.3, 5.4_
  - [ ] 2.4 Write cleanup, knowledge, and closure steps
    - Herdr workspace close + `herdr worktree remove --workspace <ID>` + branch deletion;
      `add-knowledge` skill (kb-okf MCP); set ticket `done` via `taskboard_update_ticket`
      with `tb-cli` fallback — strictly last, only after all prior steps succeed
    - _Requirements: 5.5, 5.6, 5.7, 5.8_
  - [ ] 2.5 Validate `tb-issue-finish` end to end
    - Rehearsal on a scratch ticket: review → finish → verify commit message format,
      rebase/merge, worktree cleanup, knowledge entry, ticket `done`
    - _Requirements: 5.x, 6.2_

- [ ] 3. Close out
  - [ ] 3.1 Install and register the updated skills
    - Run `task -s install` (or `install-parallel`) so the new/updated skills are installed
      and linked for supported agents; run `bats tests/` and `task --dry install` for
      sanity
    - _Requirements: 6.1, 6.2_
  - [ ] 3.2 Record decision knowledge
    - Use `add-knowledge` to record the herdr-vs-pi-a2a decision and the HERDR_ENV
      detection contract in the OpenKnowledge base
    - _Requirements: (knowledge preservation)_
  - [ ] 3.3 Final requirements traceability review
    - Walk every acceptance criterion in `requirements.md` against the two SKILL.md files;
      only then hand off for user review and explicit `tb-issue-finish AK-2`
    - _Requirements: all_
