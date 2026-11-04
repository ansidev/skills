# ASK-10 Workspace Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Herdr TUI adapter locate and close a workspace using its nested checkout path, while surfacing list failures as errors.

**Architecture:** A single Python-backed Bash helper maps a successful `herdr workspace list` JSON payload and an exact checkout path to a workspace ID. Both TUI lookup and close consume that mapping, and the three vendored adapter copies remain identical.

**Tech Stack:** Bash, Python 3 standard-library JSON parser, Python `unittest`.

**Spec:** `docs/specs/ASK-10/design.md`

## Global Constraints

- Preserve runtime JSON envelope conventions.
- Match checkout paths exactly and never close unrelated workspaces.
- Keep the three vendored `host-runtime.sh` files byte-identical.
- No optional runtime dependency such as `jq`.

## Review Focus

- Invalid or command-failure list output must be an adapter failure, never an absent workspace.
- A nested non-match must not invoke `herdr workspace close`.
- A matching path must select its associated ID, not a neighboring workspace ID.
- Lookup and close must use the same parser mapping.
- Canonical and vendored adapter copies must remain synchronized.

---

### Task 1: Add nested-JSON regression coverage

**Files:**
- Modify: `tests/test_host_runtime.py`

**Interfaces:**
- Produces: failing tests that require nested `worktree.checkout_path` matching and list-failure handling.

- [ ] **Step 1: Write failing tests**

Update matching fixtures to return objects with `workspace_id` and nested `worktree.checkout_path`. Add lookup and close tests for a failed `herdr workspace list` command; assert an error envelope and no close invocation.

- [ ] **Step 2: Run targeted tests to verify they fail**

Run: `python3 -m unittest tests.test_host_runtime.HostRuntimeContractTests.test_tui_worktree_lookup_matches_workspace_by_path tests.test_host_runtime.HostRuntimeContractTests.test_tui_workspace_close_removes_stale_issue_workspace_by_worktree_path`

Expected: FAIL because the adapter only parses a top-level `worktree_path` field.

- [ ] **Step 3: Commit**

Commit the tests together with the adapter implementation after Task 2, because the task's intended red state is not independently shippable.

### Task 2: Implement shared JSON-aware workspace matching

**Files:**
- Modify: `skills/lib/host-runtime.sh`
- Modify: `skills/kp-issue-start/lib/host-runtime.sh`
- Modify: `skills/kp-issue-finish/lib/host-runtime.sh`
- Test: `tests/test_host_runtime.py`

**Interfaces:**
- Consumes: nested test fixtures from Task 1.
- Produces: `hr_herdr_workspace_id_for_path <checkout-path>` reading JSON from stdin and printing a matching ID.

- [ ] **Step 1: Implement the helper and route lookup/close through it**

Use Python's JSON parser to select an item whose `worktree.checkout_path` exactly equals the requested path. Capture list-command failure before parsing and return a dedicated adapter error from both callers.

- [ ] **Step 2: Run targeted tests to verify they pass**

Run: `python3 -m unittest tests.test_host_runtime`

Expected: PASS.

- [ ] **Step 3: Verify vendored parity**

Run: `cmp -s skills/lib/host-runtime.sh skills/kp-issue-start/lib/host-runtime.sh && cmp -s skills/lib/host-runtime.sh skills/kp-issue-finish/lib/host-runtime.sh`

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add docs/specs/ASK-10 docs/superpowers/plans/2026-11-04-ask-10-workspace-parsing.md tests/test_host_runtime.py skills/lib/host-runtime.sh skills/kp-issue-start/lib/host-runtime.sh skills/kp-issue-finish/lib/host-runtime.sh
git commit -m "fix(ASK-10): parse nested Herdr workspace paths"
```

### Task 3: Full validation and review

**Files:**
- No production files expected.

- [ ] **Step 1: Run the full suite**

Run: `python3 -m unittest discover -s tests -v`

Expected: PASS.

- [ ] **Step 2: Review the branch against the specification**

Check the diff and ensure each requirement has direct test evidence.

- [ ] **Step 3: Transition the Kanpal issue**

After fresh verification and commit, set ASK-10 to `in-review`; do not mark it done.
