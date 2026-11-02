# ASK-4 — Requirements: Route Kanpal issue skills through host-runtime adapters

Source: kanpal issue ASK-4. Format: EARS. Builds on ASK-3's `skills/lib/host-runtime` boundary.

## User stories

1. As an agent running `kp-issue-new/start/finish`, I want every host lifecycle decision (worktree setup, agent launch, prompting, workspace cleanup) to come from the shared runtime adapter, so no skill text contains host-specific branching.
2. As an agent under **Herdr Desktop**, I want issue start/finish to work through `herdr-app`/`hc` (git-native worktrees, labeled `hc` terminals), so the Desktop flow is first-class.
3. As an agent under **Herdr TUI**, I want the existing flow preserved (worktree workspaces, pane-based agent launch, non-focusing operations).
4. As an agent **outside** any managed host, I want explicit, safe plain-git behavior: worktree ops run, host-agent ops return `NO_HOST_AGENT`, cleanup no-ops with a clear note.
5. As a skill maintainer, I want a future supported host to integrate by adding one adapter, not per-skill branches.
6. As an operator, when a lifecycle action is unavailable in the current runtime, I want clear guidance (`RUNTIME_UNSUPPORTED`/`NO_HOST_AGENT` envelopes) while Git cleanup remains available when safe.

## Acceptance criteria (EARS)

1. WHEN any `kp-issue-*` SKILL.md instructs a host operation THEN it SHALL direct the agent to `bash <skill-directory>/../lib/host-runtime <op> ...` and interpret the JSON envelope; it SHALL NOT name `herdr`/`hc`/`herdr-app` commands directly.
2. IF a skill references a removed script function (`wt-switch`, `wt-dir`, `ws-id`, `wt-del`, `start-issue`) THEN that reference SHALL be replaced by the corresponding adapter operation.
3. WHEN an issue is started THEN worktree creation/lookup and agent launch/prompt SHALL go through `host-runtime worktree-create|worktree-lookup|agent-start|agent-prompt`, with background/non-focusing behavior under both adapters.
4. WHEN an issue is finished THEN workspace cleanup SHALL go through `host-runtime workspace-close`, scoped to the issue; safe Git cleanup (worktree remove, branch -d) SHALL remain available on every runtime.
5. WHEN `kp-issue-new` confirms implementation start THEN it SHALL instruct delegating to `kp-issue-start`, never host commands directly, and SHALL NOT start implementation implicitly.
6. IF the runtime is `unknown` THEN every skill SHALL stop and report the detection error; no fallback command path.
7. WHEN a host operation is unsupported (`RUNTIME_UNSUPPORTED`) or refused (`NO_HOST_AGENT`) THEN the skill SHALL surface the envelope's error message and continue only with the operations that remain safe (e.g. git cleanup).
8. WHEN the adapter gains worktree ops THEN `outside` and `herdr-desktop` SHALL use plain `git worktree add` under `~/projects/worktrees/<repo>/<issue-key>`; the TUI adapter SHALL use `herdr worktree create` preserving current semantics.
9. WHEN a supported future host is added THEN it SHALL require only a new `hr_<op>_<runtime>` adapter plus contract tests, with no edits to skill workflow text.

## Out of scope

- Changing Kanpal workflow semantics (statuses, commit rules, review gates).
- Weakening worktree isolation rules.
- Supporting a third host beyond herdr-tui / herdr-desktop / outside.
