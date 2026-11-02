# ASK-4 — Design: Route issue skills through host-runtime adapters

## Problem

ASK-3 shipped the shared boundary (`skills/lib/host-runtime.sh`, CLI entry point, thin `script.sh` wrappers), but the three SKILL.md files were only partially touched:

- They still name TUI `herdr` commands directly (kp-issue-start's "Herdr automation workflow", kp-issue-finish's cleanup steps) and gate on `HERDR_ENV=1` instead of the adapter contract.
- They still reference script functions deleted in ASK-3: `wt-switch` (kp-issue-start, kp-issue-new), `start-issue` (kp-issue-new), `wt-del`, `ws-id`, and `herdr-workspace.sh`'s `wt-dir` (kp-issue-finish).
- The adapter itself is missing the ops the skills need: `worktree-create`, `worktree-lookup`, and a real TUI `workspace-close` (currently `RUNTIME_UNSUPPORTED`).

## Changes

### 1. `skills/lib/host-runtime.sh` — add missing ops

- `worktree-create --issue <key> --base <branch> [--repo <path>] [--focus true|false]`
  - `herdr-tui`: `herdr worktree create --branch <key> --label <key> --path <root>/<repo>/<key> [--no-focus]`, workspace id parsed from JSON. Default focus=false.
  - `herdr-desktop` / `outside`: git-native `git worktree add <root>/<repo>/<key> -b <key> <base>`; repo name from the git common dir's parent when `--repo` is omitted. Base branch is caller-supplied, never inferred.
  - Worktree root overridable via `HR_WORKTREE_ROOT` (test hook), default `~/projects/worktrees`.
- `worktree-lookup --issue <key> [--repo <path>]`
  - `herdr-tui`: `herdr workspace list` matched against `git worktree list --porcelain` by checkout path → `{"worktree_path", "workspace_id"}` (workspace_id may be empty when no workspace matches).
  - `herdr-desktop` / `outside`: `git worktree list --porcelain` only → `{"worktree_path", "workspace_id": null}`.
- `workspace-close --issue <key>`: TUI adapter now resolves the workspace (same lookup) and runs `herdr workspace close <id>`; Desktop keeps `hc kill` by label; `outside` stays a no-op success.

### 2. SKILL.md rewrites (semantics preserved)

- **kp-issue-new**: step 9 changes from invoking `script.sh start-issue` to "invoke skill `kp-issue-start <issue-key>`" — the skill-to-skill delegation the issue requires. Other steps unchanged.
- **kp-issue-start**: replace the `HERDR_ENV=1`/`herdr` automation workflow with a runtime-agnostic "managed host automation workflow": detect via `host-runtime detect`; on `herdr-tui`/`herdr-desktop` run `worktree-create`, then `agent-start`, then `agent-prompt`, all with `--issue <key>`; on `outside` do the plain git worktree flow inline; on `unknown` stop. The existing "already inside the worktree → you are the spawned agent" branch is kept. Worktree gate text keeps its HARD RULE wording; its creation branch now points at `host-runtime worktree-create` instead of `wt-switch`/raw `herdr` commands.
- **kp-issue-finish**: Cancel step 3 and Merge step 8 replace `wt-del`/`ws-id`/`herdr workspace close` with `host-runtime worktree-lookup` (pre-cleanup resolution) + `host-runtime workspace-close`. Git cleanup steps (worktree remove, `branch -d`) stay unconditional and remain described as plain git. Error envelopes from `RUNTIME_UNSUPPORTED`/`NO_HOST_AGENT` are reported, not fatal to git cleanup.

### 3. Tests (`tests/test_host_runtime.py` additions)

- `worktree-create` under desktop/outside creates a real worktree in `HR_WORKTREE_ROOT` from a temp fixture repo; TUI path stubs `herdr worktree create`.
- `worktree-lookup` finds the issue worktree; TUI path also returns the workspace id from stubbed `herdr workspace list`.
- `workspace-close` under TUI closes the resolved workspace id (stub call-log assertion).
- Existing delegation test extended: no SKILL.md references `wt-switch|ws-id|wt-del|start-issue|HERDR_ENV`.

## Preserved invariants

- Worktree HARD RULE, issue-key naming, no inferred base branch, no implicit implementation from `kp-issue-new`, git cleanup never gated on host detection, `unknown` never falls back.
