# Design Document: tb-issue-herdr-automation (AK-2)

## Overview

Two deliverables in this repository:

1. **Update `skills/tb-issue-start/SKILL.md`** — add a Herdr automation branch (worktree
   workspace + `pi` agent bootstrap), forbid auto-closing tickets, and mandate auto-staging
   of ticket-relevant changes.
2. **New `skills/tb-issue-finish/SKILL.md`** — user-invoked finish workflow: commit staged
   changes with a Conventional Commit scoped by ticket prefix, rebase onto the base branch,
   merge back, clean up the Herdr worktree workspace, record knowledge, and only then move
   the ticket to `done`.

Both skills are pure Markdown instructions (this repo contains no executable code); all
behavior is expressed as rules the coding agent must follow at runtime.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│ User inside Herdr: "/skill:tb-issue-start AK-2"            │
└──────────────┬─────────────────────────────────────────────┘
               ▼
   HERDR_ENV == 1 ?
      │ No                      │ Yes
      ▼                         ▼
 existing manual flow     Herdr automation branch (tb-issue-start)
                            1. resolve ticket (taskboard MCP / taskboard CLI)
                            2. herdr worktree create --branch <prefix> --no-focus
                            3. start pi agent in worktree pane
                               pi -a '/approval-mode act'
                            4. deliver prompt /skill:tb-issue-start <prefix>
                            5. (background) agent implements, stages changes,
                               NEVER sets ticket → done
               ▼
   User reviews diff manually

## Components and Interfaces

### 1. `skills/tb-issue-start/SKILL.md` (updated)

New sections added to the existing skill, preserving the current Input/Rules contract:

- **Herdr detection rule**: run `test "${HERDR_ENV:-}" = 1` first. Non-Herdr → existing
  instructions unchanged.
- **Herdr automation branch** (only when `HERDR_ENV=1`):
  1. Resolve ticket: `taskboard ticket list | grep <prefix>` for prefix input, or use the
     26-char ID directly; fetch details via `taskboard_get_ticket`; set status
     `in_progress` / team `agent` when `todo` (existing behavior).
  2. Create worktree workspace:
     `herdr worktree create --branch <prefix> --label <prefix> --no-focus`
     — read the workspace/pane IDs from the JSON result (do not guess them). Branch name
     is the ticket prefix, per the current manual workflow.
  3. Start the pi agent in the worktree workspace's shell pane using `herdr agent start`
     with command `pi -a '/approval-mode act'`. The exact `agent start` syntax MUST be
     discovered at runtime via `herdr agent` (installed binary is the authority).
  4. Deliver the prompt: `herdr agent prompt <agent-name> "/skill:tb-issue-start <prefix>"`
     (optionally `--wait` to wait only until the agent settles after the first turn, not
     until the whole ticket is done).
  5. Report the created workspace/agent identifiers back to the user; do not focus the
     workspace.
- **Completion rules (fixing ticket Issue 1)**: explicit rule that the agent must never
  set a ticket to `done` from `tb-issue-start`; only `tb-issue-finish` may do so, and only
  on explicit user invocation.
- **Staging rule (fixing ticket Issue 2)**: when implementation finishes, stage exactly the
  ticket-relevant files (`git add <files>`); never commit; never stage unrelated files,
  temp artifacts, or scratch output.

### 2. `skills/tb-issue-finish/SKILL.md` (new)

Frontmatter in repo convention (name, description, license: MIT). Workflow:

1. **Announce** use of the skill.
2. **Resolve ticket** (same prefix/ID contract as `tb-issue-start`).
3. **Guard rails**: inspect staged changes (`git status --porcelain`,
   `git diff --cached --stat`). If nothing is staged, stop and tell the user.
4. **Commit**: build a Conventional Commit message `<type>(<prefix>): <description>`.
   Type is inferred from the change (feat/fix/refactor/...); description summarizes the
   ticket title. Commit staged changes only.
5. **Rebase onto base branch**: determine base branch (`main` unless the repo's default
   branch differs — resolve via `git symbolic-ref refs/remotes/origin/HEAD` or ask the
   user). `git fetch <remote>` then `git rebase <base>`.
   - **On conflict**: do NOT auto-abort; stop, show `git status`, and ask the user to
     resolve manually. Ticket stays `in_progress`.
6. **Merge back**: from the base branch (`git checkout <base> && git merge <prefix-branch>`).
   Verify with `git log`.
7. **Herdr cleanup**: close the worktree workspace and remove the worktree
   (`herdr worktree remove --workspace <ID>`), delete the feature branch. Follow the
   `herdr` skill safety rules (only remove workspaces/trees this workflow created).
8. **Knowledge**: invoke the `add-knowledge` skill (kb-okf MCP) to record ticket-related
   knowledge; update existing documents when appropriate.
9. **Close ticket**: set taskboard ticket status to `done` via `taskboard_update_ticket`
   (MCP), falling back to the `taskboard` CLI per the `tb-cli` skill. Only on success of
   all prior steps.

               ▼
 User: "/skill:tb-issue-finish AK-2"      (tb-issue-finish)
   1. git commit (Conventional Commit, scope = <prefix>)
   2. rebase onto base branch (conflict → STOP, ask user)
   3. merge branch into base branch

### 3. Decision records

**Decision: use the `herdr` CLI as the automation transport (not pi-a2a)**
- **Context:** The ticket asked to research `npm:@bacnh85/pi-a2a`. Findings: pi-a2a is an
  A2A Protocol v1.0 (JSON-RPC over HTTP) extension that makes pi a callable/dispatching
  agent peer (`pi install npm:@bacnh85/pi-a2a`, `/a2a-discover`, `/a2a-send`, opt-in
  inbound `/a2a-server start` with token gating, localhost bind, isolated inbound sessions).
- **Options considered:**
  1. `herdr` CLI (`worktree create`, `agent start`, `agent prompt`) — Pros: already
     installed, lifecycle state tracking (`idle/working/blocked/done`), worktree + workspace
     management in one tool, matches the existing manual workflow. Cons: pane/agent-centric,
     not a general agent API.
  2. pi-a2a — Pros: standard protocol, bidirectional, secure inbound sessions, good for
     cross-machine/peer dispatch. Cons: requires installing/configuring the extension and
     running a server; overkill for driving one local pi session; inbound sessions are
     isolated, which does not fit an interactive worktree workflow.
- **Decision:** Option 1. Rationale: the automation target is a local, same-host worktree +
  agent bootstrap; herdr already owns worktrees, panes, and agent lifecycle. pi-a2a remains
  the recommended path if tickets are later dispatched to/from remote agents (documented in
  the knowledge base via `add-knowledge`).

**Decision: `HERDR_ENV=1` as the detection mechanism**
- Context: need reliable detection of "running inside Herdr".
- Decision: check the `HERDR_ENV=1` environment variable, per the official `herdr` skill
  ("Before issuing any control command, verify that this agent is running inside a
  Herdr-managed pane: `test \"${HERDR_ENV:-}\" = 1`").
- Rationale: it is the documented, supported signal; no probing of the `herdr` server.

**Decision: keep `tb-issue-start` non-blocking**
- Context: the manual workflow lets the user interact with the agent while it works.
- Decision: after delivering the prompt, the orchestrating agent returns control to the
  user (optionally waiting only for the first settled turn with `agent prompt --wait`).
- Rationale: implementation may take a long time and may require user interaction; the
  user reviews and then explicitly runs `tb-issue-finish`.

## Error Handling

| Scenario | Behavior |
|---|---|
| `HERDR_ENV` unset outside Herdr | Existing manual flow, unchanged |
| Ticket not found | Report "ticket does not exist", stop |
| Ticket status `done` | Report already resolved, stop (existing rule) |
| `herdr worktree create` fails | Report stderr JSON error, do not start agent |
| Agent start / prompt delivery fails | Report, leave workspace for manual inspection |
| Nothing staged at finish time | Stop, tell user; no commit, no status change |
| Rebase conflict | Stop, show conflict status, ask user to resolve manually; ticket stays `in_progress` |
| Any failure before closure | Ticket status never set to `done` (Req 3, 5.8) |

## Testing Strategy

This repo tests skills via Bats (`tests/`, helpers in `tests/helpers/common.bash` with
PATH-based command stubs) plus `task --dry` for Taskfile changes. Strategy:

- **Skill content validation**: structural checks that `SKILL.md` files keep valid YAML
  frontmatter and reference existing skills/tools (`herdr`, `add-knowledge`, `tb-cli`,
  `spec-driven-development`).
- **Behavioral workflow**: the skills are agent instructions; full end-to-end validation is
  a manual/agent-driven rehearsal — run `tb-issue-start` inside a Herdr test session against
  a scratch ticket, then `tb-issue-finish`, using git stubs where needed. Add a Bats test
  only where a checkable contract exists (e.g. commit message format helper if one is
  extracted).
- **Manual checklist** mapped to EARS criteria in `requirements.md` (one checklist item per
  acceptance criterion).

   4. herdr: close worktree workspace, herdr worktree remove
   5. add-knowledge skill (kb-okf MCP)
   6. taskboard ticket status → done
```

