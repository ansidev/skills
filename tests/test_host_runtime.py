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
        # Hermetic by construction: the invoking shell's HERDR_ENV, PATH, and
        # live host binaries must never influence detection under test.
        env = os.environ.copy()
        env.pop("HERDR_ENV", None)
        self.base_env = env | {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HR_WORKTREE_ROOT": str(Path(self.temp.name) / "worktrees"),
        }
        self.worktree_root = Path(self.temp.name) / "worktrees"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def stub(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(f"#!/usr/bin/env bash\n{body}\n")
        path.chmod(0o755)

    def fixture_repo(self) -> Path:
        """A small real git repo (one commit on main) for worktree ops."""
        repo = Path(self.temp.name) / "fixture-repo"
        repo.mkdir()
        for cmd in (
            ["git", "init", "-b", "main", str(repo)],
            ["git", "-C", str(repo), "config", "user.email", "t@example.com"],
            ["git", "-C", str(repo), "config", "commit.gpgsign", "false"],
            ["git", "-C", str(repo), "config", "user.name", "t"],
            ["git", "-C", str(repo), "commit", "--allow-empty", "-m", "seed"],
        ):
            subprocess.run(cmd, check=True, capture_output=True)
        return repo

    def run_cli(self, *args: str, env: dict[str, str] | None = None, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CLI), *args],
            text=True,
            capture_output=True,
            env=env or self.base_env,
            cwd=cwd,
            check=False,
        )

    def result(self, *args: str, env: dict[str, str] | None = None, cwd: str | None = None) -> tuple[subprocess.CompletedProcess[str], dict]:
        completed = self.run_cli(*args, env=env, cwd=cwd)
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

    def test_desktop_with_missing_hc_is_an_actionable_error(self) -> None:
        self.stub("herdr-app", 'exit 0')
        completed, result = self.result("detect")
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "DETECT_FAILED")

    def test_invoking_shell_environment_never_leaks_into_detection(self) -> None:
        # A polluted caller environment must not flip the outcome either way.
        polluted = self.base_env | {"HERDR_ENV": "1"}
        completed, result = self.result("detect", env=polluted)
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "DETECT_FAILED")

    # ------------------------------------------------------------------
    # Worktree lifecycle (desktop / outside): real git ops on a fixture repo
    # ------------------------------------------------------------------

    def test_outside_worktree_lifecycle_creates_isolated_issue_worktree(self) -> None:
        repo = self.fixture_repo()
        _, created = self.result(
            "worktree-create", "--issue", "ASK-5", "--base", "main",
            "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(created["ok"])
        expected = self.worktree_root / repo.name / "ASK-5"
        self.assertEqual(Path(created["data"]["worktree_path"]).resolve(), expected.resolve())
        self.assertTrue(expected.is_dir())
        branch = subprocess.run(
            ["git", "-C", str(expected), "branch", "--show-current"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        self.assertEqual(branch, "ASK-5")
        _, lookup = self.result(
            "worktree-lookup", "--issue", "ASK-5", "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(lookup["ok"])
        self.assertEqual(Path(lookup["data"]["worktree_path"]).resolve(), expected.resolve())
        self.assertIsNone(lookup["data"]["workspace_id"])
        _, removed = self.result(
            "worktree-remove", "--issue", "ASK-5", "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(removed["ok"])
        self.assertFalse(expected.exists())
        branches = subprocess.run(
            ["git", "-C", str(repo), "branch", "--list", "ASK-5"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        self.assertEqual(branches, "")

    def test_outside_worktree_remove_force_handles_dirty_worktree(self) -> None:
        repo = self.fixture_repo()
        _, created = self.result(
            "worktree-create", "--issue", "ASK-9", "--base", "main",
            "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(created["ok"])
        dirty = Path(created["data"]["worktree_path"]) / "uncommitted.txt"
        dirty.write_text("uncommitted\n")
        completed, removed = self.result(
            "worktree-remove", "--issue", "ASK-9", "--force", "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(removed["ok"])
        self.assertEqual(completed.returncode, 0)
        self.assertFalse(Path(created["data"]["worktree_path"]).exists())

    def test_worktree_lookup_without_worktree_fails(self) -> None:
        repo = self.fixture_repo()
        completed, result = self.result(
            "worktree-lookup", "--issue", "NOPE-1", "--repo", str(repo), cwd=str(repo),
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "WORKTREE_NOT_FOUND")

    # ------------------------------------------------------------------
    # Worktree ops under herdr-tui: exact commands, stubbed herdr
    # ------------------------------------------------------------------

    def test_tui_worktree_create_uses_no_focus_and_issue_key_naming(self) -> None:
        log = Path(self.temp.name) / "herdr.log"
        self.stub("herdr", f'printf \'%s\\n\' "$*" >> "{log}"; printf \'{{"workspace_id":"w9"}}\\n\'')
        repo = self.fixture_repo()
        _, created = self.result(
            "worktree-create", "--issue", "KP-7", "--base", "main",
            "--repo", str(repo), env=self.base_env | {"HERDR_ENV": "1"},
        )
        self.assertTrue(created["ok"])
        self.assertEqual(created["data"]["workspace_id"], "w9")
        expected = self.worktree_root / repo.name / "KP-7"
        self.assertEqual(Path(created["data"]["worktree_path"]), expected)
        calls = log.read_text()
        self.assertIn("worktree create --branch KP-7 --label KP-7", calls)
        self.assertIn("--no-focus", calls)
        self.assertIn(str(expected), calls)

    def test_tui_worktree_create_focus_true_omits_no_focus_flag(self) -> None:
        log = Path(self.temp.name) / "herdr.log"
        self.stub("herdr", f'printf \'%s\\n\' "$*" >> "{log}"; printf \'{{"workspace_id":"w9"}}\\n\'')
        repo = self.fixture_repo()
        _, created = self.result(
            "worktree-create", "--issue", "KP-7", "--base", "main",
            "--repo", str(repo), "--focus", "true",
            env=self.base_env | {"HERDR_ENV": "1"},
        )
        self.assertTrue(created["ok"])
        self.assertNotIn("--no-focus", log.read_text())

    def test_tui_worktree_create_failure_without_repo_name(self) -> None:
        self.stub("herdr", 'exit 0')
        workdir = Path(self.temp.name) / "not-a-repo"
        workdir.mkdir()
        completed, result = self.result(
            "worktree-create", "--issue", "KP-7", "--base", "main",
            env=self.base_env | {"HERDR_ENV": "1"}, cwd=str(workdir),
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "WORKTREE_CREATE_FAILED")

    def test_tui_worktree_lookup_matches_workspace_by_path(self) -> None:
        repo = self.fixture_repo()
        self.result(
            "worktree-create", "--issue", "KP-7", "--base", "main",
            "--repo", str(repo), cwd=str(repo),
        )
        wt_path = os.path.realpath(self.worktree_root / repo.name / "KP-7")
        self.stub(
            "herdr",
            f'''if test "$1 $2" = "workspace list"; then
  printf \'{{"workspace_id":"w1","worktree_path":"/decoy/other"}}\\n\'
  printf \'{{"workspace_id":"w2","worktree_path":"{wt_path}"}}\\n\'
  exit 0
fi
exit 1''',
        )
        _, lookup = self.result(
            "worktree-lookup", "--issue", "KP-7", "--repo", str(repo),
            env=self.base_env | {"HERDR_ENV": "1"}, cwd=str(repo),
        )
        self.assertTrue(lookup["ok"])
        self.assertEqual(lookup["data"]["workspace_id"], "w2")

    def test_tui_worktree_remove_is_refused(self) -> None:
        self.stub("herdr", 'exit 0')
        completed, result = self.result(
            "worktree-remove", "--issue", "KP-7",
            env=self.base_env | {"HERDR_ENV": "1"},
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "RUNTIME_UNSUPPORTED")

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

    def test_no_skill_md_references_removed_host_functions(self) -> None:
        import re
        removed = re.compile(r"wt-switch|ws-id|wt-del|start-issue|herdr-workspace\.sh")
        for skill in ("kp-issue-new", "kp-issue-start", "kp-issue-finish"):
            text = (ROOT / "skills" / skill / "SKILL.md").read_text()
            self.assertIsNone(removed.search(text), skill)

    def test_every_result_is_a_single_normalized_json_envelope(self) -> None:
        completed = self.run_cli("agent-prompt", "--issue", "ASK-3", "--text", "hello")
        self.assertEqual(len(completed.stdout.splitlines()), 1)
        result = json.loads(completed.stdout)
        self.assertEqual(set(result), {"ok", "runtime", "op", "error"})
        self.assertEqual(set(result["error"]), {"code", "message"})


if __name__ == "__main__":
    unittest.main()
