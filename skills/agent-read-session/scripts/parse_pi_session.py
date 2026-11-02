#!/usr/bin/env python3
"""Normalize a Pi session JSONL file into an agent-readable transcript."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def text_from(content: Any) -> str:
    """Keep visible text blocks and exclude private thinking blocks."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""

    return "\n".join(
        block["text"]
        for block in content
        if isinstance(block, dict)
        and block.get("type") == "text"
        and isinstance(block.get("text"), str)
    )


def tool_calls_from(content: Any) -> list[dict[str, Any]]:
    """Extract assistant tool-call blocks without altering structured arguments."""
    if not isinstance(content, list):
        return []

    return [
        {
            "id": block.get("id"),
            "name": block.get("name"),
            "arguments": block.get("arguments", {}),
        }
        for block in content
        if isinstance(block, dict) and block.get("type") == "toolCall"
    ]


def normalize(session_path: Path) -> dict[str, Any]:
    metadata: dict[str, Any] | None = None
    events: list[dict[str, Any]] = []

    for line in session_path.read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue

        if record.get("type") == "session":
            metadata = record
            continue

        if record.get("type") == "model_change":
            events.append({"type": "model_change", "model": record.get("modelId", record.get("model", "unknown"))})
            continue

        if record.get("type") != "message" or not isinstance(record.get("message"), dict):
            continue

        message = record["message"]
        role = message.get("role")
        if role not in {"user", "assistant", "tool"}:
            continue

        content = text_from(message.get("content"))
        tool_calls = tool_calls_from(message.get("content"))
        event: dict[str, Any] = {"role": role}
        if message.get("toolCallId"):
            event["toolCallId"] = message["toolCallId"]
        if content:
            event["content"] = content
        if tool_calls:
            event["toolCalls"] = tool_calls
        if content or tool_calls:
            events.append(event)

    if metadata is None:
        raise ValueError(f"No session metadata found in {session_path}")

    return {
        "session": {
            "id": metadata.get("id"),
            "cwd": metadata.get("cwd"),
            "startedAt": metadata.get("timestamp"),
            "version": metadata.get("version"),
        },
        "events": events,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/parse_pi_session.py <session.jsonl>", file=sys.stderr)
        return 2

    try:
        print(json.dumps(normalize(Path(sys.argv[1])), indent=2))
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
