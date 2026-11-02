"""Contract tests for the kp-issue host-runtime integration boundary."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "skills" / "lib" / "host-runtime"


class HostRuntimeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self.base_env = os.environ | {"PATH": f"{self.bin}:/usr/bin:/bin", "HR_WORKTREE_ROOT": str(Path(self.temp.name) / "worktrees")}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def stub(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(f"#!/usr/bin/env bash\n{body}\n")
        path.chmod(0o755)

    def run_cli(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CLI), *args],
            text=True,
            capture_output=True,
            env=env or self.base_env,
            check=False,
        )

    def result(self, *args: str, env: dict[str, str] | None = None) -> tuple[subprocess.CompletedProcess[str], dict]:
        completed = self.run_cli(*args, env=env)
        return completed, json.loads(completed.stdout)

    def test_detects_outside_when_no_host_signals_exist(self) -> None:
        completed, result = self.result("detect")
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(result, {"ok": True, "runtime": "outside", "op": "detect", "data": {"runtime": "outside"}})

    def test_detects_tui_from_environment_and_herdr_binary(self) -> None:
        self.stub("herdr", 'printf "{}\\n"')
        completed, result = self.result("detect", env=self.base_env | {"HERDR_ENV": "1"})
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(result["runtime"], "herdr-tui")
        self.assertTrue(result["ok"])

    def test_tui_signal_without_herdr_is_an_actionable_error(self) -> None:
        completed, result = self.result("detect", env=self.base_env | {"HERDR_ENV": "1"})
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["runtime"], "unknown")
        self.assertEqual(result["error"]["code"], "DETECT_FAILED")
        self.assertIn("HERDR_ENV=1", result["error"]["message"])

    def test_detects_desktop_only_when_app_and_reachable_core_exist(self) -> None:
        self.stub("herdr-app", 'exit 0')
        self.stub("hc", 'test "$1" = server && test "$2" = status')
        completed, result = self.result("detect")
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(result["runtime"], "herdr-desktop")

    def test_desktop_with_unreachable_core_is_an_actionable_error(self) -> None:
        self.stub("herdr-app", 'exit 0')
        self.stub("hc", 'exit 7')
        completed, result = self.result("detect")
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["runtime"], "unknown")
        self.assertEqual(result["error"]["code"], "DETECT_FAILED")
        self.assertIn("hc", result["error"]["message"])

    def test_outside_agent_launch_is_refused_without_running_a_host_command(self) -> None:
        completed, result = self.result("agent-start", "--issue", "ASK-3", "--args", "pi")
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["runtime"], "outside")
        self.assertEqual(result["error"]["code"], "NO_HOST_AGENT")

    def test_desktop_agent_lifecycle_uses_labeled_hc_terminal(self) -> None:
        log = Path(self.temp.name) / "hc.log"
        self.stub("herdr-app", 'exit 0')
        self.stub("hc", f'''printf '%s\\n' "$*" >> "{log}"
if test "$1" = server; then exit 0; fi
if test "$1" = run; then printf '{{"address":"t7"}}\\n'; exit 0; fi
if test "$1" = ls; then printf '{{"terminals":[{{"address":"t7"}}]}}\\n'; exit 0; fi
if test "$1" = send || test "$1" = kill; then exit 0; fi
exit 1''')
        _, started = self.result("agent-start", "--issue", "ASK-3", "--args", "pi -a /approval-mode act")
        self.assertTrue(started["ok"])
        self.assertEqual(started["data"]["terminal"], "t7")
        _, prompted = self.result("agent-prompt", "--issue", "ASK-3", "--text", "/kp-issue-start ASK-3")
        self.assertTrue(prompted["ok"])
        _, closed = self.result("workspace-close", "--issue", "ASK-3")
        self.assertTrue(closed["ok"])
        calls = log.read_text()
        self.assertIn("run --bg --keep --label herdr.issue=ASK-3", calls)
        self.assertIn("send t7 /kp-issue-start ASK-3", calls)
        self.assertIn("kill t7", calls)

    def test_tui_agent_lifecycle_uses_structured_pane_and_agent_commands(self) -> None:
        log = Path(self.temp.name) / "herdr.log"
        self.stub("herdr", f'''printf '%s\\n' "$*" >> "{log}"
if test "$1 $2" = "pane list"; then printf '{{"result":{{"panes":[{{"pane_id":"w1:p2"}}]}}}}\\n'; exit 0; fi
if test "$1 $2" = "agent start" || test "$1 $2" = "agent prompt" || test "$1 $2" = "workspace close"; then printf '{{"result":{{}}}}\\n'; exit 0; fi
exit 1''')
        env = self.base_env | {"HERDR_ENV": "1"}
        _, started = self.result("agent-start", "--issue", "ASK-3", "--workspace", "w1", "--args", "pi", env=env)
        self.assertTrue(started["ok"])
        _, prompted = self.result("agent-prompt", "--issue", "ASK-3", "--text", "start", env=env)
        self.assertTrue(prompted["ok"])
        calls = log.read_text()
        self.assertIn("pane list --workspace w1", calls)
        self.assertIn("agent start issue-ask-3 --kind pi --pane w1:p2", calls)
        self.assertIn("agent prompt issue-ask-3 start", calls)

    def test_each_issue_script_delegates_to_the_shared_runtime_boundary(self) -> None:
        for skill in ("kp-issue-new", "kp-issue-start", "kp-issue-finish"):
            script = (ROOT / "skills" / skill / "scripts" / "script.sh").read_text()
            self.assertIn("host-runtime.sh", script, skill)
            self.assertNotIn("function wt-switch()", script, skill)

    def test_every_result_is_a_single_normalized_json_envelope(self) -> None:
        completed = self.run_cli("agent-prompt", "--issue", "ASK-3", "--text", "hello")
        self.assertEqual(len(completed.stdout.splitlines()), 1)
        result = json.loads(completed.stdout)
        self.assertEqual(set(result), {"ok", "runtime", "op", "error"})
        self.assertEqual(set(result["error"]), {"code", "message"})


if __name__ == "__main__":
    unittest.main()
