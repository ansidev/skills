"""Behavior tests for the kp-issue skills across host runtimes.

Covers the script-level behavior of kp-issue-new / kp-issue-start /
kp-issue-finish under herdr-tui, herdr-desktop, and outside-host cases using
stubbed host binaries and a fixture git repo — never a live workspace, sidebar
order, or hard-coded IDs.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ROOT / "skills"


class IssueSkillBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
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

    def run_script(self, skill: str, *args: str, env: dict[str, str] | None = None, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
        script = SKILLS / skill / "scripts" / "script.sh"
        return subprocess.run(
            ["bash", str(script), *args],
            text=True,
            capture_output=True,
            env=env or self.base_env,
            cwd=cwd,
            check=False,
        )

    def script_result(self, skill: str, *args: str, env: dict[str, str] | None = None, cwd: str | None = None) -> tuple[subprocess.CompletedProcess[str], dict]:
        completed = self.run_script(skill, *args, env=env, cwd=cwd)
        return completed, json.loads(completed.stdout)

    # ------------------------------------------------------------------
    # kp-issue-new: routing only — it must never touch host binaries
    # ------------------------------------------------------------------

    def test_kp_issue_new_delegates_to_kp_issue_start_and_never_hosts(self) -> None:
        text = (SKILLS / "kp-issue-new" / "SKILL.md").read_text()
        self.assertIn("kp-issue-start", text)
        self.assertIn("kanpal", text)
        for forbidden in ("herdr worktree", "herdr agent", "herdr workspace", "hc run", "hc send", "hc kill"):
            self.assertNotIn(forbidden, text)

    # ------------------------------------------------------------------
    # kp-issue-start across runtimes
    # ------------------------------------------------------------------

    def test_kp_issue_start_detects_outside_and_creates_worktree(self) -> None:
        repo = self.fixture_repo()
        _, detected = self.script_result("kp-issue-start", "detect", cwd=str(repo))
        self.assertTrue(detected["ok"])
        self.assertEqual(detected["runtime"], "outside")
        _, created = self.script_result(
            "kp-issue-start", "worktree-create", "--issue", "ASK-5",
            "--base", "main", "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(created["ok"])
        expected = self.worktree_root / repo.name / "ASK-5"
        self.assertEqual(Path(created["data"]["worktree_path"]).resolve(), expected.resolve())
        self.assertTrue(expected.is_dir())

    def test_kp_issue_start_refuses_agent_ops_outside(self) -> None:
        repo = self.fixture_repo()
        completed, result = self.script_result(
            "kp-issue-start", "agent-start", "--issue", "ASK-5",
            "--args", "pi", cwd=str(repo),
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "NO_HOST_AGENT")

    def test_kp_issue_start_tui_creates_worktree_without_focus(self) -> None:
        log = Path(self.temp.name) / "herdr.log"
        self.stub("herdr", f'''printf '%s\\n' "$*" >> "{log}"
if test "$1 $2" = "pane list"; then printf '{{"result":{{"panes":[{{"pane_id":"w1:p1"}}]}}}}\\n'; exit 0; fi
if test "$1 $2" = "worktree create" || test "$1 $2" = "agent start" || test "$1 $2" = "agent prompt" || test "$1 $2" = "workspace close"; then printf '{{"result":{{"workspace_id":"w1"}}}}\\n'; exit 0; fi
exit 1''')
        repo = self.fixture_repo()
        env = self.base_env | {"HERDR_ENV": "1"}
        _, created = self.script_result(
            "kp-issue-start", "worktree-create", "--issue", "KP-7",
            "--base", "main", "--repo", str(repo), env=env,
        )
        self.assertTrue(created["ok"])
        self.assertIn("--no-focus", log.read_text())
        _, started = self.script_result(
            "kp-issue-start", "agent-start", "--issue", "KP-7",
            "--workspace", "w1", "--args", "pi", env=env,
        )
        self.assertTrue(started["ok"])
        self.assertEqual(started["data"]["pane_id"], "w1:p1")
        completed, _ = self.script_result(
            "kp-issue-start", "agent-start", "--issue", "KP-7",
            "--args", "pi", env=env,
        )
        self.assertNotEqual(completed.returncode, 0)

    def test_kp_issue_start_unknown_runtime_is_a_stop_condition(self) -> None:
        self.stub("herdr-app", "exit 0")
        self.stub("hc", "exit 7")
        repo = self.fixture_repo()
        completed, result = self.script_result(
            "kp-issue-start", "worktree-create", "--issue", "KP-7",
            "--base", "main", "--repo", str(repo), cwd=str(repo),
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["runtime"], "unknown")
        self.assertEqual(result["error"]["code"], "DETECT_FAILED")

    def test_kp_issue_start_worktree_lookup_missing_issue_fails(self) -> None:
        repo = self.fixture_repo()
        completed, result = self.script_result(
            "kp-issue-start", "worktree-lookup", "--issue", "NOPE-1",
            "--repo", str(repo), cwd=str(repo),
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "WORKTREE_NOT_FOUND")

    # ------------------------------------------------------------------
    # kp-issue-finish cleanup behavior
    # ------------------------------------------------------------------

    def test_kp_issue_finish_workspace_close_outside_is_noop_success(self) -> None:
        repo = self.fixture_repo()
        _, closed = self.script_result(
            "kp-issue-finish", "workspace-close", "--issue", "ASK-5", cwd=str(repo),
        )
        self.assertTrue(closed["ok"])
        self.assertEqual(closed["data"]["closed"], 0)

    def test_kp_issue_finish_closes_only_the_issue_workspace_on_tui(self) -> None:
        repo = self.fixture_repo()
        self.script_result(
            "kp-issue-start", "worktree-create", "--issue", "KP-7",
            "--base", "main", "--repo", str(repo), cwd=str(repo),
        )
        wt_path = os.path.realpath(self.worktree_root / repo.name / "KP-7")
        log = Path(self.temp.name) / "herdr.log"
        self.stub("herdr", f'''printf '%s\\n' "$*" >> "{log}"
if test "$1 $2" = "workspace list"; then
  printf '{{"workspace_id":"w1","worktree_path":"/decoy/other"}}\\n'
  printf '{{"workspace_id":"w2","worktree_path":"{wt_path}"}}\\n'
  exit 0
fi
if test "$1 $2 $3" = "workspace close w2"; then exit 0; fi
exit 1''')
        env = self.base_env | {"HERDR_ENV": "1"}
        _, closed = self.script_result(
            "kp-issue-finish", "workspace-close", "--issue", "KP-7", env=env, cwd=str(repo),
        )
        self.assertTrue(closed["ok"])
        self.assertEqual(closed["data"]["closed"], 1)
        self.assertEqual(closed["data"]["workspace_id"], "w2")
        self.assertIn("workspace close w2", log.read_text())
        self.assertNotIn("workspace close w1", log.read_text())

    def test_kp_issue_finish_worktree_remove_refused_on_tui(self) -> None:
        self.stub("herdr", "exit 0")
        completed, result = self.script_result(
            "kp-issue-finish", "worktree-remove", "--issue", "KP-7",
            env=self.base_env | {"HERDR_ENV": "1"},
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(result["error"]["code"], "RUNTIME_UNSUPPORTED")

    def test_kp_issue_finish_worktree_remove_on_outside(self) -> None:
        repo = self.fixture_repo()
        self.script_result(
            "kp-issue-start", "worktree-create", "--issue", "ASK-5",
            "--base", "main", "--repo", str(repo), cwd=str(repo),
        )
        wt = self.worktree_root / repo.name / "ASK-5"
        self.assertTrue(wt.is_dir())
        _, removed = self.script_result(
            "kp-issue-finish", "worktree-remove", "--issue", "ASK-5",
            "--repo", str(repo), cwd=str(repo),
        )
        self.assertTrue(removed["ok"])
        self.assertEqual(removed["data"]["removed"], 1)
        self.assertFalse(wt.exists())

    def test_kp_issue_finish_host_failure_does_not_block_git_cleanup_paths(self) -> None:
        # Host binaries failing must produce typed failure envelopes the skill
        # can report, not crash with a non-JSON exit.
        repo = self.fixture_repo()
        self.stub("herdr-app", "exit 0")
        self.stub("hc", 'test "$1" = server && test "$2" = status; exit 0')
        _, closed = self.script_result(
            "kp-issue-finish", "workspace-close", "--issue", "ASK-5", cwd=str(repo),
        )
        self.assertTrue(closed["ok"])  # desktop close is best-effort; kill of absent terminal counts as closed:0
        self.assertEqual(closed["data"]["closed"], 0)


if __name__ == "__main__":
    unittest.main()
