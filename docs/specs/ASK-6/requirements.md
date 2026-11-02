# ASK-6 — Requirements: Pi hook reporting blocked state to Herdr on ask_user_question

## Introduction

Add a Pi extension hook under `hooks/pi/` that reports `state=blocked` to Herdr whenever
the `ask_user_question` tool is invoked, so the Herdr sidebar can show the agent as blocked
while it waits for user approval.

## Requirements

### Requirement 1 — No-op outside Herdr
1. WHEN `HERDR_ENV` is not `1`, OR either `HERDR_BIN_PATH` or `HERDR_PANE_ID` is unset/empty, THEN the extension SHALL register nothing and make no side effects.

### Requirement 2 — Fire-and-forget report on ask_user_question
1. WHEN `HERDR_ENV=1` and both bin/pane env vars are set, THEN whenever Pi emits a `tool_call` event for `ask_user_question`, the extension SHALL spawn `"$HERDR_BIN_PATH" pane report-agent "$HERDR_PANE_ID" --source pi --agent pi --state blocked --message "Approval: ⚡ ACT" --seq <n>`.
2. `--seq` SHALL be a monotonically increasing value (e.g. `Date.now()` ms).
3. The subprocess SHALL run in the background with a short timeout and SHALL NOT block the agent turn; failures SHALL be ignored.

### Requirement 3 — Do not alter tool behavior
1. The hook SHALL NOT block or mutate the `ask_user_question` invocation.

## Out of scope
- Reporting `idle`/`working`; releasing on exit; resume commands.
