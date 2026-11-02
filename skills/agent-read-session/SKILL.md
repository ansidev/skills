---
name: agent-read-session
description: "Use when a user asks to read, inspect, summarize, or recover a Pi agent session by agent and session ID. Supports /agent-read-session [--agent|-a pi] --session|-s <session-id>."
---

# agent-read-session

Convert a stored Pi session JSONL file into a compact, chronological transcript that another agent can safely read and reason over. Do not dump the raw JSONL unless the user explicitly requests it.

## Supported agent

| Agent | Session root | Status |
| --- | --- | --- |
| `pi` | `~/.pi/agent/sessions/` | Supported |

If `--agent` is not `pi`, state that it is unsupported and stop.

## Input contract

```text
/agent-read-session --session <session-id>
/agent-read-session --agent pi --session <session-id>
/agent-read-session -a pi -s <session-id>
```

- `--agent`/`-a` is optional; defaults to `pi`. If provided, it must be `pi`.
- `--session`/`-s` is required; it is the UUID in the JSONL filename and in the first `session` record's `id` field.
- Search recursively, because session directories are named after their working directories. Do not expect the ID to appear in a top-level listing.

## Procedure

1. Locate exactly one matching JSONL file beneath `~/.pi/agent/sessions/`.

   ```bash
   find ~/.pi/agent/sessions -type f -name "*_<session-id>.jsonl"
   ```

2. Parse it with the bundled normalizer. The command returns valid JSON with session metadata and normalized events.

   ```bash
   python3 scripts/parse_pi_session.py <absolute-session-path>
   ```

3. Read the normalized JSON and report the useful conversation chronologically. Include the session ID, working directory, user and assistant messages, tool calls/results, errors, test outcomes, changed paths, and user-visible decisions.

4. Keep output concise by summarizing verbose command output. Preserve exact error messages, commands, paths, IDs, URLs, and test results when they matter to the user's request.

## Normalization rules

| JSONL content | Transcript handling |
| --- | --- |
| `session` record | Keep `id`, `cwd`, start time, and version. |
| User/assistant text blocks | Keep verbatim and preserve order. |
| Assistant `toolCall` blocks | Keep tool name, call ID, and structured arguments. |
| Tool text responses | Keep as a tool event; summarize only when verbose. |
| `thinking` blocks | Omit. Never expose hidden reasoning. |
| Model/thinking-level changes | Keep model changes; omit thinking-level events unless explicitly requested. |
| UI metadata, token usage, stream deltas, custom records | Omit unless they are required to explain an error. |
| Invalid JSONL lines or unknown records | Skip and mention only if parsing was materially incomplete. |

## Example

```text
/agent-read-session -a pi -s 01a19bb5-3941-7212-a457-48f5b52f27f7
```

The answer should be an agent-readable transcript and brief context summary, not raw JSONL.

## Common mistakes

- Running `ls ~/.pi/agent/sessions/ | grep <session-id>` only searches the top level; session files are nested.
- Using `ll` in a shell where it is not configured; use `ls -la` or `find`.
- Reading hidden `thinking` blocks into the transcript.
- Treating the filename match as sufficient when several files match; validate the session metadata ID before reporting a result.
