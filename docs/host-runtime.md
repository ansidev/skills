# Host Runtime Adapter Contract

`skills/lib/host-runtime.sh` is the single integration boundary between the
`kp-issue-*` skills and the host (terminal multiplexer / desktop app) they run
inside. Skills never invoke host binaries directly; they call the
`skills/lib/host-runtime` CLI (or source the library) and act only on the
normalized JSON envelope it returns.

This document is the contract a new host adapter must satisfy, and the
procedure for adding one.

## Runtime detection

`host-runtime detect` resolves exactly one runtime id, in this order:

| Order | Signals | Result |
|---|---|---|
| 1 | `HERDR_ENV=1` **and** `herdr` on PATH | `herdr-tui` |
| 2 | `HERDR_ENV=1` but no `herdr` on PATH | `unknown` (error) |
| 3 | `herdr-app` on PATH **and** `hc` on PATH **and** `hc server status` succeeds | `herdr-desktop` |
| 4 | `herdr-app` present but `hc` missing or `hc server status` fails | `unknown` (error) |
| 5 | no host signals | `outside` |

Rules that are part of the contract:

- Detection uses only environment variables and binary probes. It never
  inspects UI state, workspace lists, or sidebar ordering.
- An ambiguous state (`unknown`) is an error outcome with code
  `DETECT_FAILED` and a human-readable message. It is **never** a fallback to
  another runtime's command path.
- `outside` is a valid runtime: worktree operations run through plain git,
  and host-agent operations are refused (see the capabilities matrix).

## The envelope contract

Every invocation prints exactly one JSON line on stdout:

```json
{ "ok": true,  "runtime": "herdr-tui", "op": "worktree-create",
  "data": { "worktree_path": "...", "workspace_id": "w1" } }
```

```json
{ "ok": false, "runtime": "outside", "op": "agent-start",
  "error": { "code": "NO_HOST_AGENT", "message": "..." } }
```

- Success: key set is exactly `ok`, `runtime`, `op`, `data`.
- Failure: key set is exactly `ok`, `runtime`, `op`, `error`; `error` has
  exactly `code` and `message`.
- Exit code is `0` on success, `1` on failure. stderr is for human-facing
  progress only.

## Operations and command mappings

When [worktrunk](https://github.com/bgp/worktrunk) (`wt`) is on PATH, the
git-native worktree create/lookup/remove paths go through `wt switch --create`
/ `wt list --branches --format json` / `wt remove` instead (wt's own path
template wins), falling back to plain git when wt fails.

| Op | herdr-tui | herdr-desktop | outside |
|---|---|---|---|
| `worktree-create --issue K --base B [--repo R] [--focus true\|false]` | `herdr worktree create --branch K --label K --path <root>/<repo>/K [--no-focus]`; workspace id parsed from JSON | git-native: `git worktree add <root>/<repo>/K -b K B` | git-native (same as desktop) |
| `worktree-lookup --issue K [--repo R]` | `herdr workspace list` matched against `git worktree list --porcelain` by checkout path | `git worktree list --porcelain` | `git worktree list --porcelain` |
| `worktree-remove --issue K [--force]` | **refused** (`RUNTIME_UNSUPPORTED`) — close the Herdr workspace instead | `wt remove K` or `git worktree remove [+ --force]` + `git branch -D K` | same as desktop |
| `agent-start --issue K --workspace W --args "..."` (TUI) / `--args "..."` (desktop) | `herdr agent start issue-<lowercased K> --kind pi --pane <pane-id> -- <args>`; pane resolved via `herdr pane list --workspace W` | `hc run --bg --keep --label herdr.issue=K -- <args>` | refused (`NO_HOST_AGENT`) |
| `agent-prompt --issue K --text "..."` | `herdr agent prompt issue-<lowercased K> "<text>"` | `hc send <terminal> <text>`; terminal resolved via `hc ls --label herdr.issue=K` | refused (`NO_HOST_AGENT`) |
| `workspace-close --issue K [--worktree-path P]` | resolve workspace id (same lookup as `worktree-lookup`), then `herdr workspace close <id>` | `hc kill` every live terminal labeled `herdr.issue=K`, plus every live terminal whose cwd is `P` (or inside it) — desktop-app terminals carry no `herdr.issue` label, so `--worktree-path` (resolved at pre-flight, before the worktree is removed) is the reliable match | no-op success (`closed: 0`) |

`<root>` is `$HR_WORKTREE_ROOT` (default `~/projects/worktrees`). `<repo>` is
the leaf name of `--repo` when given, otherwise the parent of the git common
dir. `detect` works on every runtime.

## Capabilities matrix

| Op | herdr-tui | herdr-desktop | outside |
|---|---|---|---|
| detect | ✅ | ✅ | ✅ |
| worktree-create | ✅ (via herdr) | ✅ (git/wt) | ✅ (git/wt) |
| worktree-lookup | ✅ (+ workspace id) | ✅ | ✅ |
| worktree-remove | ❌ `RUNTIME_UNSUPPORTED` | ✅ | ✅ |
| agent-start | ✅ | ✅ | ❌ `NO_HOST_AGENT` |
| agent-prompt | ✅ | ✅ | ❌ `NO_HOST_AGENT` |
| workspace-close | ✅ | ✅ | ✅ no-op |

Explicit refusals are part of the contract, not gaps: a caller that cannot do
something gets a typed error envelope it can report, instead of a silent skip
or a wrong-host command.

## Error codes

| Code | Meaning | Caller guidance |
|---|---|---|
| `DETECT_FAILED` | host signals are contradictory or incomplete | stop and report the message; never fall back to another host's commands |
| `INVALID_ARGS` | unknown op, unknown option, or a required option is missing | fix the invocation |
| `NO_HOST_AGENT` | host-agent op outside a managed host | run the git-native flow inline; report that no agent could be launched |
| `RUNTIME_UNSUPPORTED` | this runtime deliberately does not implement the op | report it and use the documented alternative |
| `WORKTREE_CREATE_FAILED` | `git worktree add` / `wt switch` / `herdr worktree create` failed | report the embedded message; the worktree HARD RULE means you stop, not fall back to the main checkout |
| `WORKTREE_NOT_FOUND` | no worktree exists on the issue branch | treat per skill context (create one, or report as already removed) |
| `WORKTREE_REMOVE_FAILED` | removal failed | report; do not retry blindly |
| `AGENT_START_FAILED` | pane lookup or agent launch failed | report; do not retry blindly |
| `AGENT_PROMPT_FAILED` | prompt delivery failed | report; do not retry blindly |
| `CLOSE_FAILED` | workspace close failed | report; git cleanup continues |

## Safety invariants

- **Issue-key isolation.** Worktrees are created at
  `<root>/<repo>/<issue-key>` on a branch named exactly `<issue-key>` (e.g.
  `KP-7`, never the bare prefix `KP`). Herdr workspaces are labeled with the
  same key; Desktop terminals are labeled `herdr.issue=<key>` so cleanup is
  deterministic and scoped.
- **No focus stealing by default.** TUI worktree creation passes
  `--no-focus` unless `--focus true` is given; Desktop launches use
  `--bg --keep`.
- **Cleanup independence.** Git worktree/branch cleanup is a plain-git
  concern and is never gated on host detection. Host cleanup
  (`workspace-close`) is best-effort: its failure envelope is reported but
  does not stop git cleanup.
- **No blind retries.** Every host command's output is captured; failures
  become one envelope. Nothing is retried automatically.
- **No inference.** The base branch is always caller-supplied; IDs (pane,
  workspace, terminal) are always read from command output, never assumed.

## Adding a new host runtime

Extension is adapter-shaped: add a runtime id and its adapter functions; do
not branch inside an existing adapter's functions (an `if` on the new host
inside `hr_agent_start_tui` is a design smell — the dispatch in `hr_run` is
the only place runtime ids are selected per op).

1. **Choose the runtime id** (e.g. `acme-term`). It becomes the value of
   `runtime` in every envelope and the suffix of every adapter function.
2. **Add detection** in `hr_detect_runtime`: decide which signal(s) identify
   the host (env var, binary, reachability probe). Keep the ordering rules:
   first unambiguous match wins; an ambiguous state must set
   `HR_DETECT_ERROR` and return `unknown` with exit 1, never fall through.
3. **Implement the adapters**: for each op the host supports, add
   `hr_<op>_<runtime>` (e.g. `hr_worktree_create_acme_term`). Contract for
   each function:
   - print a success envelope via `hr_ok <runtime> <op> '<data-json>'`, or
     fail via `hr_fail <runtime> <op> <ERROR_CODE> "<message>"` (returns 1);
   - capture all host-command output; parse IDs from the host's own output,
     never assume them;
   - refuse unsupported ops with `NO_HOST_AGENT` (agent ops) or
     `RUNTIME_UNSUPPORTED` (everything else) instead of skipping.
4. **Wire the dispatch** in `hr_run`: add `<runtime>` to each op's `case`
   arm with the required argument validation. Ops the host does not support
   get an arm that fails with `RUNTIME_UNSUPPORTED`.
5. **Add contract tests** to `tests/test_host_runtime.py` and behavior tests
   to `tests/test_issue_skills.py`: detection success and failure paths, one
   full lifecycle per op with stubbed host binaries and call-log assertions
   on the exact commands, and the refusal paths. A runtime that fails these
   tests does not ship.
6. **Document it here**: add the runtime to the detection table, both op
   tables, and the capabilities matrix, and list any new error codes.

### Checklist for a new adapter

- [ ] runtime id added to `hr_detect_runtime` with an actionable ambiguous-state error
- [ ] `hr_<op>_<runtime>` for every supported op; refusals for the rest
- [ ] `hr_run` dispatch arms with argument validation
- [ ] contract + behavior tests with stubbed binaries and call-log assertions
- [ ] detection table, op tables, capabilities matrix, error codes updated in this file
