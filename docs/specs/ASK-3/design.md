# ASK-3 — Design: Host-runtime integration boundary

## Overview

Extract all host (Herdr) interaction out of the three duplicated per-skill `scripts/script.sh` copies into one shared runtime library (`skills/lib/host-runtime.sh`) plus a single entry-point script (`skills/lib/host-runtime` CLI). Each skill's `script.sh` becomes a thin wrapper that sources the library and dispatches to it. Detection, the result envelope, and the adapter contract live in one place.

## Architecture

```
caller (SKILL.md text or script.sh)
        │  sources / execs
        ▼
skills/lib/host-runtime.sh          ← runtime detection, envelope, dispatch
        │ selects adapter by runtime
        ├── adapter: herdr-tui      (herdr CLI, existing flow)
        ├── adapter: herdr-desktop  (herdr-app for window-side, hc for terminals/agents)
        └── adapter: outside        (no host commands; plain git worktree flow)
```

Detection precedes any adapter call. `unknown` is an error outcome, never a fallback.

## Components and interfaces

### `skills/lib/host-runtime.sh` (sourced library)

- `hr_detect_runtime` → echoes `herdr-tui | herdr-desktop | outside`; on an ambiguous state sets `HR_DETECT_ERROR` (human-readable) and echoes `unknown`, exit 1.
  Detection order (first match wins): `HERDR_ENV=1` → `herdr` on PATH ? `herdr-tui` : unknown. Else `herdr-app` on PATH → `hc` on PATH AND `hc server status` succeeds ? `herdr-desktop` : unknown. Else `outside`.
- `hr_require <runtime...>` → detect, verify the runtime is allowed, else emit envelope with `RUNTIME_UNSUPPORTED` and exit 1.
- `hr_envelope <ok> <runtime> <op> <data-json|error-code> [message]` → prints the single normalized JSON shape.
- `hr_run <op> -- <args...>` → detects, selects adapter, dispatches to `hr_<op>_<runtime>`, wraps the result in the envelope. Exit 1 on failure with `{"ok":false,...}`.

### `skills/lib/host-runtime` (executable entry point)

```
host-runtime detect
host-runtime worktree-create  --issue <key> --base <branch> [--repo <path>] [--focus true|false]
host-runtime worktree-lookup  --issue <key> [--repo <path>]
host-runtime agent-start      --issue <key> [--agent pi] [--kind pi] [--args "..."]
host-runtime agent-prompt     --issue <key> --text "<prompt>"
host-runtime workspace-close  --issue <key>
```

All output is one JSON envelope on stdout; human-facing progress goes to stderr.

### Adapters (functions `hr_<op>_<runtime>` inside the library)

| Op | herdr-tui (unchanged behavior) | herdr-desktop | outside |
|---|---|---|---|
| worktree-create | `herdr worktree create --branch/--label/--path/--cwd --base --[no-]focus`; parse workspace id from JSON | `git worktree add` under `~/projects/worktrees/<repo>/<issue>` (Desktop does not own TUI worktree workspaces; worktree isolation stays git-native) | `git worktree add` (same as today's non-Herdr branch of the skills) |
| worktree-lookup | `herdr workspace list` + `git worktree list --porcelain`, match by checkout path | `git worktree list --porcelain` | `git worktree list --porcelain` |
| agent-start | `herdr agent start <name> --kind pi --pane <pane-id> -- <args>` | `hc run --bg --keep --label herdr.space=<space> --label herdr.tab=<tab> -- <agent argv>`; window-side placement (if requested) via `herdr-app do` | error `NO_HOST_AGENT` |
| agent-prompt | `herdr agent prompt <name> "<text>"` | `hc send <terminal> <text>` | error `NO_HOST_AGENT` |
| workspace-close | `herdr workspace close <id>` (+ `herdr worktree remove` if attached) | `hc kill <terminal>` (scoped to terminals started for this issue, matched by label `herdr.issue=<key>`) | no-op success (git worktree cleanup is the caller's job, per kp-issue-finish) |

Desktop launches tag terminals with `herdr.issue=<issue-key>` so cleanup is deterministic and scoped.

### Skill changes

- `skills/kp-issue-{new,start,finish}/scripts/script.sh`: replace duplicated bodies with `source ../../lib/host-runtime.sh` and thin wrappers preserving the existing public function names (`wt-switch`, `ws-id`, `start-issue`, `wt-del`, …) so current SKILL.md text and muscle memory keep working. Where the text references Herdr directly (Rules 6–7, worktree gate, automation workflow), generalize the wording to "the detected host runtime" while keeping the `HERDR_ENV=1` fast check as a cheap pre-probe (it remains a valid TUI signal, never a requirement).
- SKILL.md edits: replace TUI-only instructions with "use the host-runtime CLI; on `unknown` runtime, stop and report". The worktree HARD RULE text is unchanged — worktree isolation never depends on the host.

## Data models

Envelope (the only caller-visible shape):

```json
{ "ok": true,  "runtime": "herdr-tui", "op": "worktree-create",
  "data": { "worktree_path": "...", "workspace_id": "w1", "pane_id": "w1:p1" } }
{ "ok": false, "runtime": "unknown", "op": "detect",
  "error": { "code": "DETECT_FAILED", "message": "HERDR_ENV=1 but 'herdr' not on PATH" } }
```

Error codes: `DETECT_FAILED`, `RUNTIME_UNSUPPORTED`, `NO_HOST_AGENT`, `WORKTREE_CREATE_FAILED`, `WORKTREE_NOT_FOUND`, `WORKSPACE_NOT_FOUND`, `AGENT_START_FAILED`, `AGENT_PROMPT_FAILED`, `CLOSE_FAILED`, `INVALID_ARGS`.

## Error handling

- Every host command runs with output captured; non-zero exit or unparseable JSON → failure envelope with the op and runtime named. Nothing is retried blindly.
- `unknown` runtime → skills stop; no silent fallback (TUI commands under Desktop or vice versa are never attempted).
- `outside` runtime → only git worktree operations run; any host-agent op returns `NO_HOST_AGENT` instead of being skipped silently.

## Testing strategy

Bash contract tests (repo already has a `tests/` convention; add `tests/test_host_runtime.bash`, plain-bash runner consistent with `test_agent_read_session.py` style and runnable standalone; also add a pytest wrapper for `python3 -m pytest tests/`):

- Stub `herdr`, `herdr-app`, `hc` on PATH (call-log stubs, like `tests/helpers/common.bash`).
- Cases: TUI detected; Desktop detected (`hc server status` ok); Desktop with `hc` missing → unknown; Desktop with `hc` failing → unknown; TUI with `herdr` missing → unknown; no signals → outside; each op under each runtime; envelope shape (jq-validated) for success and failure; scoped cleanup only touches labeled resources; worktree ops never call host binaries under `outside`.
- Determinism: detection uses only env + binary probes, no example IDs or ordering.

## Decisions

### Decision: shared bash library + CLI entry point, not per-skill copies
**Context:** Today each kp-issue skill ships an identical ~8KB `script.sh` with all Herdr logic inline.
**Options:** (1) keep three copies and add Desktop branches to each; (2) shared library + entry point; (3) rewrite in Python.
**Decision:** Option 2.
**Rationale:** Skills already source bash (`script.sh`) and SKILL.md text invokes `bash <skill-dir>/scripts/script.sh <fn>`; a single library removes the triplication (the actual defect), keeps the calling convention, and bash is already the dependency floor (jq/git). Python would add a runtime dependency to every agent harness for no contract benefit.

### Decision: Desktop worktrees stay git-native
**Context:** `herdr worktree` is a TUI CLI surface; Desktop (`hc`/`herdr-app`) has no equivalent documented worktree-workspace command.
**Options:** (1) force `herdr` CLI under Desktop; (2) git-native worktrees with `hc`-launched agents attached.
**Decision:** Option 2. Worktree isolation is a git concern and must hold on every host; only agent lifecycle is host-specific.

### Decision: `herdr.issue=<key>` label for Desktop cleanup scoping
**Rationale:** `hc` has no workspaces; labels are the documented tagging mechanism (`--label k=v`), so cleanup filters by label instead of guessing which terminal belongs to which issue.
