# ASK-5 — Design: Verify and document extensible host-runtime support

## Overview

ASK-3 shipped the boundary, ASK-4 routed the skills through it. ASK-5 hardens both with (a) a hermetic, comprehensive test suite and (b) a maintainer-facing adapter-contract document whose "add a new host" procedure is adapter-shaped, not branch-shaped. No production behavior changes except fixing test hermeticity inside the tests themselves.

## Problem found during requirements

`tests/test_host_runtime.py` inherits the invoking shell's environment: `HERDR_ENV=1`, a real `herdr` on PATH, or a stubbed-over PATH leak into every subprocess, so `test_detects_outside_when_no_host_signals_exist` and friends fail on a Herdr-hosted machine. Tests must control their own environment.

## Changes

### 1. `tests/test_host_runtime.py` — hermetic base + expanded contract coverage

- `setUp` builds the env explicitly: `PATH` = stub dir + system dirs, `HERDR_ENV` deleted, `HR_WORKTREE_ROOT` pointed at the per-test temp dir. Every invocation uses only this env; nothing from `os.environ` leaks except explicitly added per-test overrides.
- New helper: `fixture_repo()` — a bare-initialized then seeded temp git repo (`git init`, one commit on `main`) used for real worktree ops under desktop/outside runtimes; `git -C` scoped so the outer repo is never touched.
- New contract tests (per issue scope):
  - Detection matrix (exists, extended): no signals → outside; `HERDR_ENV=1`+`herdr` → herdr-tui; `HERDR_ENV=1` without `herdr` → `DETECT_FAILED`; `herdr-app`+`hc server status` ok → herdr-desktop; `herdr-app` without `hc` → `DETECT_FAILED`; `herdr-app`+failing `hc` → `DETECT_FAILED`.
  - Worktree lifecycle under desktop and outside against the fixture repo: `worktree-create` produces the real directory `<root>/<repo>/ASK-X`, branch `ASK-X` exists, `worktree-lookup` finds it (workspace_id null), `worktree-remove` removes it and deletes the branch; `--force` path exercised via a dirty worktree.
  - Worktree-create under herdr-tui with stubbed `herdr`: exact command `worktree create --branch <key> --label <key> --path <root>/<repo>/<key> --no-focus` asserted from the call log; focus=true omits `--no-focus`; `--repo` override changes the path's repo component; missing `--repo` and no git repo in cwd → `WORKTREE_CREATE_FAILED`.
  - Worktree-lookup under herdr-tui matches the workspace by path from stubbed `herdr workspace list` JSON lines; no match → workspace_id null.
  - `worktree-remove` under herdr-tui → `RUNTIME_UNSUPPORTED` (refusal preserved).
  - Agent ops: outside → `NO_HOST_AGENT` with empty host call log; desktop full lifecycle (`hc run --bg --keep --label herdr.issue=<key>`, `hc ls`, `hc send`, `hc kill`) asserted on exact arguments; TUI lifecycle (`pane list --workspace`, `agent start issue-<lowerkey> --kind pi --pane <pane>`, `agent prompt`, `workspace close <id>`).
  - Scoping: `workspace-close` on desktop only kills the terminal whose label is `herdr.issue=<key>`; a decoy terminal with a different label in the stub output is not killed.
  - Envelope contract: every result is exactly one JSON line with the fixed key set; failure envelopes carry `error.code`; unknown op and unknown option → `INVALID_ARGS`.
  - Skill routing: each of the three `script.sh` files sources `host-runtime.sh` and dispatches to it; no kp-issue SKILL.md mentions `wt-switch|ws-id|wt-del|start-issue|herdr-workspace.sh`.
- Keep tests free of live workspace/sidebar order and hard-coded IDs: all IDs (`w1:p2`, `t7`, workspace ids) come from stub output, asserted by value not by position.

### 2. `tests/test_issue_skills.py` — behavior tests for the three skills

Subprocess-driven, using the same hermetic env and stub binaries, plus a fixture repo:

- `kp-issue-new`: SKILL.md routing assertions only (no script behavior): must reference `kanpal` MCP usage, must NOT construct host commands, must delegate confirmed starts to `kp-issue-start`.
- `kp-issue-start` (outside runtime): running `script.sh worktree-create --issue <key> --base main --repo <fixture>` in the fixture repo creates the worktree at `<root>/<repo>/<key>` and prints a valid envelope; `script.sh detect` reports `outside` with `HERDR_ENV` scrubbed; agent ops refuse with `NO_HOST_AGENT`.
- `kp-issue-start` (herdr-tui): `script.sh worktree-create` with stubbed `herdr` emits the no-focus command; `script.sh agent-start` without `--workspace` → `INVALID_ARGS`.
- `kp-issue-finish`: `script.sh workspace-close --issue <key>` under outside → no-op success (`closed:0`); under herdr-tui closes the resolved workspace id; `worktree-remove` under herdr-tui → `RUNTIME_UNSUPPORTED`.
- Failure paths: nonexistent issue key → `WORKTREE_NOT_FOUND` from lookup; `herdr` stub failing → `*_FAILED` codes.

### 3. `docs/host-runtime.md` — the adapter contract

Structure:

1. **Overview** — one shared boundary; skills never call host binaries directly.
2. **Runtime detection** — the ordered signals (`HERDR_ENV=1` + `herdr` → herdr-tui; `herdr-app` + reachable `hc` → herdr-desktop; otherwise outside), ambiguity → `unknown` + `DETECT_FAILED`, never a fallback.
3. **The envelope contract** — exact JSON shape, key set, one line on stdout, exit-code semantics.
4. **Operations and per-adapter command mappings** — table of op × runtime with the exact commands (`herdr worktree create …`, `hc run --bg --keep --label herdr.issue=<key> …`, git-native fallbacks, worktrunk precedence when `wt` exists).
5. **Capabilities matrix** — which ops each runtime supports; explicit refusals (`NO_HOST_AGENT`, `RUNTIME_UNSUPPORTED`) as part of the contract, not bugs.
6. **Error codes** — full list with meaning and caller guidance.
7. **Adding a new host runtime** — step-by-step: (1) choose a runtime id; (2) implement `hr_detect` signal(s) in `hr_detect_runtime`; (3) implement `hr_<op>_<runtime>` for each op (supported ops real, unsupported ops fail with `NO_HOST_AGENT`/`RUNTIME_UNSUPPORTED`); (4) wire the runtime into `hr_run`'s per-op dispatch; (5) add contract tests to the matrix; (6) document the commands in this file's tables. Explicitly framed as "add an adapter"; branching inside an existing adapter's functions is an anti-pattern called out in the doc.
8. **Worktree safety invariants** — issue-key naming, `HR_WORKTREE_ROOT`, focus defaults, no-cd behavior.

## Preserved invariants

No changes to `host-runtime.sh` behavior, envelope shape, error codes, or SKILL.md semantics. Tests are the deliverable, plus documentation; the only library-adjacent edits are inside test files.

## Testing strategy

The tests themselves are the deliverable (see Changes 1–2). Validation: `python3 -m unittest discover -s tests` from both a plain shell and a `HERDR_ENV=1` shell must pass identically.

## Decisions

### Decision: fix hermeticity in the tests, not in the library
**Context:** The library reads `HERDR_ENV` from the environment by design (that is the detection contract); the failures come from the tests inheriting the caller's environment.
**Options:** (1) make the library scrub env; (2) make tests construct their own env.
**Decision:** Option 2.
**Rationale:** Scrubbing env inside the library would change the detection contract the library exists to implement. Test isolation is a test responsibility.

### Decision: python unittest, not bats, for the new behavior tests
**Context:** ASK-3's design mentioned a possible bats file; the shipped suite is `python3 -m unittest` and `tests/helpers/common.bash` (bats-style helpers) is currently unused by any runner.
**Decision:** Add `tests/test_issue_skills.py` in the same unittest style as `test_host_runtime.py`; leave `common.bash` untouched.
**Rationale:** One runner, one dependency floor (python3 + git), consistent with the existing convention; the bats helpers predate the boundary work and are out of ASK-5 scope.

### Decision: behavior tests assert on stub call logs, not on live Herdr
**Context:** The issue forbids reliance on live workspace/sidebar order or hard-coded IDs.
**Decision:** All host binaries are stubbed per test; every assertion reads either the returned JSON envelope or a call log written by the stubs.
**Rationale:** Deterministic on any machine; also the only way to assert the exact commands (safety invariants) rather than their side effects.
