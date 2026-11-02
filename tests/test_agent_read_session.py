"""Behavioral tests for the Pi session transcript parser.

These tests fail if visible text, tool calls, session metadata, or hidden-thinking
redaction is changed unintentionally.
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "skills" / "agent-read-session" / "scripts" / "parse_pi_session.py"


class ParsePiSessionTests(unittest.TestCase):
    def test_normalizes_visible_conversation_and_excludes_hidden_thinking(self) -> None:
        """A parser regression must not leak thinking or drop visible tool context."""
        records = [
            {
                "type": "session",
                "version": 3,
                "id": "test-session",
                "timestamp": "2026-01-01T00:00:00.000Z",
                "cwd": "/tmp/example",
            },
            {"type": "model_change", "modelId": "example-model"},
            {
                "type": "message",
                "message": {
                    "role": "user",
                    "content": [{"type": "text", "text": "Read the latest report."}],
                },
            },
            {
                "type": "message",
                "message": {
                    "role": "assistant",
                    "content": [
                        {"type": "thinking", "thinking": "hidden chain of thought"},
                        {"type": "text", "text": "I will inspect it."},
                        {
                            "type": "toolCall",
                            "id": "call-1",
                            "name": "functions.read",
                            "arguments": {"path": "/tmp/report.md"},
                        },
                    ],
                },
            },
            {
                "type": "message",
                "message": {
                    "role": "tool",
                    "toolCallId": "call-1",
                    "content": [{"type": "text", "text": "Report is ready."}],
                },
            },
            {"type": "custom", "customType": "unrelated", "data": {"ignored": True}},
        ]

        with tempfile.TemporaryDirectory() as directory:
            session_path = Path(directory) / "fixture.jsonl"
            session_path.write_text("\n".join(json.dumps(record) for record in records), encoding="utf-8")
            completed = subprocess.run(
                ["python3", str(PARSER), str(session_path)],
                check=True,
                capture_output=True,
                text=True,
            )

        transcript = json.loads(completed.stdout)
        self.assertEqual(
            transcript["session"],
            {
                "id": "test-session",
                "cwd": "/tmp/example",
                "startedAt": "2026-01-01T00:00:00.000Z",
                "version": 3,
            },
        )
        self.assertEqual(
            transcript["events"],
            [
                {"type": "model_change", "model": "example-model"},
                {"role": "user", "content": "Read the latest report."},
                {
                    "role": "assistant",
                    "content": "I will inspect it.",
                    "toolCalls": [
                        {
                            "id": "call-1",
                            "name": "functions.read",
                            "arguments": {"path": "/tmp/report.md"},
                        }
                    ],
                },
                {"role": "tool", "toolCallId": "call-1", "content": "Report is ready."},
            ],
        )
        self.assertNotIn("hidden chain of thought", completed.stdout)


if __name__ == "__main__":
    unittest.main()
