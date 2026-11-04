# Design: repair Herdr TUI workspace discovery

## Overview

Replace the two line-oriented `sed` scans of `herdr workspace list` with one
JSON-aware helper. The helper receives the raw list response and an exact
worktree path, emits the corresponding `workspace_id`, and is consumed by both
TUI lookup and close operations.

## Architecture

`skills/lib/host-runtime.sh` remains the host boundary. The TUI operations
first resolve the issue's Git worktree path when necessary, execute `herdr
workspace list`, and pass its JSON into the shared parser. Lookup serializes
the resulting ID (or `null`) in its existing success envelope; close uses it
for `herdr workspace close`.

The parser will use the already-required `python3` runtime rather than a
line-oriented shell parser or an optional `jq` dependency. It accepts either a
top-level workspace list or newline-delimited direct workspace objects, but it
will require both `workspace_id` and `worktree.checkout_path` on a direct
candidate before returning it. It deliberately does not recursively traverse
metadata or other nested response objects.

## Components and interfaces

| Component | Responsibility |
| --- | --- |
| `hr_herdr_workspace_id_for_path` | Parse a successful Herdr list payload and print the matching workspace ID, if any. |
| `hr_worktree_lookup_tui` | Fail on list-command failure; otherwise return the Git worktree path plus matched ID or `null`. |
| `hr_workspace_close_tui` | Fail on list-command failure; otherwise close only the matched ID or report confirmed absence. |
| `tests/test_host_runtime.py` | Stub representative nested JSON and assert matching, absence, failure, and exact close invocation. |

## Data model

The relevant Herdr item is:

```json
{
  "workspace_id": "wC5",
  "worktree": { "checkout_path": "/absolute/issue/path" }
}
```

The comparison key is the exact `checkout_path` string. A missing path or ID
is not a match.

## Decision

Use a shared Python JSON parser invoked from Bash.

- A shared parser avoids lookup and close drifting apart.
- Python is already used by this adapter, so this adds no dependency.
- `jq` would be concise but is not guaranteed in the host environment.
- Continuing with `sed` cannot safely traverse nested JSON or distinguish a
  command failure from an empty result.

## Error handling

- A non-zero `herdr workspace list` exits through `hr_fail` with a dedicated
  list error and includes the command output for diagnosis.
- Valid list JSON with no exact match remains the sole path that returns the
  existing no-workspace result.
- A failed `herdr workspace close` keeps the existing `CLOSE_FAILED` result.

## Testing strategy

Use isolated Herdr stubs to test a matching nested path, a nested non-match,
and a failed list command for both lookup and close behavior. Run the targeted
host-runtime test module and the complete Python suite.
