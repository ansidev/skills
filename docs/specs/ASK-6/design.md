# ASK-6 — Design: Pi extension hook for Herdr blocked state

## Overview
A single TypeScript Pi extension at `hooks/pi/herdr-blocked-reporter.ts`, auto-loadable via `pi -e` or copied to the user's extensions dir.

## Components
- Guard: only activate when `HERDR_ENV === "1"` and both `HERDR_BIN_PATH`, `HERDR_PANE_ID` are set.
- Hook `pi.on("tool_call", ...)`: filter `event.toolName === "ask_user_question"`; spawn the herdr CLI with `spawn(..., { stdio: "ignore", detached: false })`, add a 2s kill timer, ignore errors, `unref()` so it cannot keep the process alive.
- `--seq` = `Date.now()` (ms), monotonically increasing enough for one process.

## Notes
- Never await the subprocess; never mutate `event.input`; never return a block decision.
