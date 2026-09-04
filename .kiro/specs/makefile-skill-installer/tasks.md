# Implementation Plan: Makefile Skill Installer

## Overview

Implement a single `Makefile` with four public targets (`help`, `prepare`, `install`, `install-all`) and a Bats-based test suite that covers all eleven correctness properties. All shell logic lives inside Make recipes joined with `\` continuations (no `.ONESHELL`). The agent directory map is a `case` statement rather than Make variable indirection. Stubs on `PATH` mock `gh` and `brew` for integration and property tests.

## Tasks

- [x] 1. Bootstrap project layout and test infrastructure
  - Create directory structure: `tests/`, `tests/stubs/`, `tests/helpers/`
  - Add `.gitignore` entries for temp test artefacts
  - Write a `tests/helpers/common.bash` Bats helper: `setup`/`teardown` for temp dir, PATH stub injection, and helper assertions (`assert_exit`, `assert_output_contains`, `assert_stderr_contains`, `assert_symlink`)
  - _Requirements: none (infrastructure only)_

- [x] 2. Implement the `help` target and global variable block
  - [x] 2.1 Write global variable declarations and `help` target
    - Declare `agents ?= pi,codex,opencode`, `scope ?= user`, `debug ?= false` with `?=`
    - Set `.DEFAULT_GOAL := help`
    - Implement `help` with `@echo` lines listing all four targets and their one-line descriptions, plus each global variable with kind and default
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2_
  - [ ]* 2.2 Write example tests for `help` target
    - Invoke `make` with no args; assert exit 0 and that stdout contains `prepare`, `install-all`, `install`, `help`, and each variable name with its default
    - _Requirements: 1.1, 1.2, 1.3_

- [x] 3. Implement the `global_agent_skill_dir_map` shell `case` statement helper
  - [x] 3.1 Add the agent directory `case` block inside the `install` recipe
    - Write the shell `case "$$agent" in … esac` block covering all five agents: `claude-code`, `codex`, `opencode`, `pi`, `github-copilot`
    - Each branch sets `skill_dir` using `$$HOME/…` (shell variable, not Make `$(HOME)`)
    - Default branch sets `skill_dir=""`
    - _Requirements: 3.1, 3.2, 3.3_
  - [ ]* 3.2 Write property test P11 — `$HOME` expanded in map paths
    - For each of the five agents, invoke the `case` block in isolation (via a thin Bats wrapper) and assert `skill_dir` starts with the actual `$HOME` value, not the literal string
    - **Property 11: Agent directory map paths expand `$HOME`**
    - **Validates: Requirements 3.2**

- [x] 4. Implement the `prepare` target
  - [x] 4.1 Write the `prepare` recipe
    - Use `command -v brew` to detect Homebrew; skip both `brew trust` and `brew install gh` (exit 0) when absent
    - When `brew` present: run `brew trust /opt/homebrew`; on non-zero exit print error to stderr and exit 1
    - When `brew` present and `gh` absent (`command -v gh` fails): run `brew install gh`; on non-zero exit print error to stderr and exit 1
    - When `gh` already present: skip `brew install gh`
    - On success print a completion message to stdout
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_
  - [ ]* 4.2 Write example tests for `prepare` target
    - Test: `brew` absent → exit 0, no brew/gh commands invoked (stub call log empty)
    - Test: `brew` present, `gh` present → `brew trust` runs, `brew install gh` skipped
    - Test: `brew` present, `gh` absent → both `brew trust` and `brew install gh` run
    - Test: `brew trust` fails → stderr contains error, exit non-zero
    - Test: `brew install gh` fails → stderr contains error, exit non-zero
    - _Requirements: 4.1–4.7_

- [x] 5. Implement `install` — input validation and default resolution
  - [x] 5.1 Write the `install` recipe preamble: validation and default resolution
    - Validate `repo` non-empty; if absent/empty print usage to stderr (listing `repo` as required plus each optional param with default) and exit 1
    - Validate `scope` ∈ {user, project}; if invalid print error to stderr and exit 1
    - Resolve `skills` to `*` when unset; resolve `debug` to `false` when unset or unrecognised
    - Resolve `agents` to `universal` when unset; treat empty/whitespace-only as unset
    - _Requirements: 5.1, 5.2, 5.3, 6.1–6.5, 2.5, 2.6_
  - [ ]* 5.2 Write example tests for `install` validation
    - Test: `make install` (no repo) → stderr contains usage, exit non-zero, no gh called
    - Test: `make install repo=x scope=bad` → stderr error, exit non-zero
    - Test: `make install repo=x` → exit 0 (with stubbed gh)
    - _Requirements: 5.1, 5.2, 2.6_

- [x] 6. Implement `install` — agent array resolution
  - [x] 6.1 Write the `agent_arr` construction shell block
    - Split `agents_resolved` on `,` using IFS; trim whitespace from each token; drop empty tokens
    - Append `universal` if not already present (exact case-sensitive match)
    - If result is empty after trimming, set `agent_arr` to contain only `universal`
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - [ ]* 6.2 Write property test P1 — caller-supplied agents used verbatim
    - Generate 100 random non-empty comma-delimited agent lists; for each assert `agent_arr` contains exactly the trimmed tokens plus `universal` (if not already present)
    - **Property 1: Caller-supplied `agents` is used verbatim**
    - **Validates: Requirements 2.3, 7.1, 7.2, 7.3**
  - [ ]* 6.3 Write property test P3 — `universal` always in `agent_arr` exactly once
    - Generate 100 random comma-delimited strings (with/without `universal`, empty, whitespace-only); assert `universal` appears exactly once in the resolved `agent_arr`
    - **Property 3: `agent_arr` always contains `universal` exactly once**
    - **Validates: Requirements 7.2, 7.3, 7.4**
  - [ ]* 6.4 Write property test P2 — invalid scope always rejected
    - Generate 100 random strings guaranteed to be neither `user` nor `project`; invoke `make install repo=x scope=<string>` and assert exit non-zero, stderr non-empty, no gh call logged
    - **Property 2: Invalid `scope` values are always rejected**
    - **Validates: Requirements 2.6**

- [x] 7. Implement `install` — wildcard install path
  - [x] 7.1 Write the `skills == "*"` branch of the `install` recipe
    - When `skills_resolved` equals `*`: run `gh extension install --repo "$$repo" --all --upstream --force --scope "$$scope" --agent universal`
    - When `debug=true`: print the fully-expanded command to stdout instead of executing it
    - When `debug=false`: print one summary line with resolved `repo`, `scope`, and agent (`universal`)
    - When `debug` is neither `true` nor `false`: treat as `false`
    - _Requirements: 8.1, 8.2, 8.3, 8.4_
  - [ ]* 7.2 Write property test P4 — wildcard runs exactly one `gh --all` command
    - Generate 100 random (repo, scope) pairs; invoke `make install repo=$$repo scope=$$scope skills=*`; assert stub gh log contains exactly one call with `--all`, `--agent universal`, correct repo and scope
    - **Property 4: Wildcard install runs exactly one `gh` command targeting `universal`**
    - **Validates: Requirements 8.1**

- [x] 8. Implement `install` — named-skill install path and unrecognized-agent warnings
  - [x] 8.1 Write the named-skill loop in the `install` recipe
    - Split `skills_resolved` on `,`; for each skill:
      - Run `gh extension install --repo "$$repo" --upstream --force --scope "$$scope" --agent universal`
      - Iterate over `agent_arr`; for each agent: run the `case` block to resolve `skill_dir`; if `skill_dir` is empty record agent as unrecognized; else run `ln -sf ~/.agents/skills/$$skill "$$skill_dir/$$skill"`
      - When `debug=true` print each `gh` and `ln` command before executing
      - When `debug=false` print one summary line per skill listing skill name and target agents
    - After loop: if unrecognized agents recorded, print warning summary to stderr listing each name exactly once; exit 0
    - _Requirements: 9.1–9.6, 10.1–10.4, 14.2, 14.4, 14.5_
  - [ ]* 8.2 Write property test P5 — named-skill runs one `gh` per skill
    - Generate 100 random non-empty comma-delimited skill lists with a fixed repo; assert stub gh log contains exactly one call per skill targeting `universal`
    - **Property 5: Named-skill install runs one `gh` universal install per skill**
    - **Validates: Requirements 9.1, 9.2**
  - [ ]* 8.3 Write property test P6 — symlinks created for every recognized agent
    - Generate 100 random subsets of the five known agents with random skill names; assert `ln -sf` created the correct symlink for every agent in the subset
    - **Property 6: Symlinks are created for every recognized agent in `agent_arr`**
    - **Validates: Requirements 9.3**
  - [ ]* 8.4 Write property test P7 — unrecognized agents warn, exit 0
    - Generate 100 random agent lists containing at least one unknown agent name; assert exit 0, stderr contains warning listing each unknown name exactly once, recognized-agent symlinks still created
    - **Property 7: Unrecognized agents are warned about, but do not cause failure**
    - **Validates: Requirements 10.1, 10.2, 10.4**

- [x] 9. Checkpoint — verify core install behavior
  - Ensure all tests pass so far, ask the user if questions arise.

- [x] 10. Implement `install-all` target
  - [x] 10.1 Write the `install-all` recipe
    - Check `skills.txt` exists in CWD; if not print error to stderr naming the file and exit 1
    - Read with `while IFS= read -r line || [ -n "$$line" ]`; skip blank lines; skip and warn on lines without `|`
    - For each valid line: split on first `|` → `repo`, `skills`; invoke `$(MAKE) install repo=$$repo skills=$$skills agents=$(agents) scope=user debug=$(debug)`; capture exit status
    - Accumulate failures (repo|skills pairs); after loop: if failures exist print failure summary to stdout and exit 1; else print success summary and exit 0
    - _Requirements: 11.1, 11.2, 12.1–12.5, 13.1–13.5_
  - [ ]* 10.2 Write property test P8 — `install-all` processes every valid line
    - Generate 100 random `skills.txt` contents (varying blank lines, comment lines, no-trailing-newline); count valid lines N; invoke `make install-all`; assert `$(MAKE) install` called exactly N times
    - **Property 8: `install-all` processes every valid line in `skills.txt`**
    - **Validates: Requirements 12.1, 12.2, 12.3, 12.4, 13.1**
  - [ ]* 10.3 Write property test P9 — `install-all` failure summary complete and accurate
    - Generate 100 scenarios with a random subset of entries made to fail (via a stub gh that fails for specific repos); assert failure summary lists exactly the failing entries, exit non-zero, no successful entries appear
    - **Property 9: `install-all` failure summary is complete and accurate**
    - **Validates: Requirements 13.1, 13.2, 13.3**
  - [ ]* 10.4 Write property test P10 — `debug=true` propagates to all sub-makes
    - Generate 10 random `skills.txt` contents; invoke `make install-all debug=true`; assert every `$(MAKE) install` sub-invocation in the log received `debug=true`
    - **Property 10: `debug=true` propagates to all sub-makes**
    - **Validates: Requirements 13.5, 14.3**
  - [ ]* 10.5 Write example tests for `install-all` manifest validation
    - Test: `skills.txt` absent → stderr names file, exit non-zero, no installs run
    - Test: line without `|` → warning to stderr, that line skipped, others processed
    - Test: all lines succeed → success summary to stdout, exit 0
    - _Requirements: 11.1, 11.2, 12.5, 13.4_

- [x] 11. Final checkpoint — full test suite
  - Ensure all Bats tests pass (`bats tests/`), Makefile syntax is valid (`make -n help` exits 0), ask the user if any questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- All recipes use `\` line-continuation — no `.ONESHELL` (macOS GNU Make 3.81 incompatibility)
- The agent directory map lives in a shell `case` statement, not Make variable indirection
- Stubs placed in a temp directory prepended to `PATH` mock `gh` and `brew`; each stub appends its invocation to a call log file for assertions
- Property tests run 100 iterations each using a lightweight Bats-based random input generator in `tests/helpers/common.bash`
- Each property test is annotated with its property number and the requirements clause it validates
- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["2.1"] },
    { "id": 1, "tasks": ["2.2", "3.1"] },
    { "id": 2, "tasks": ["3.2", "4.1"] },
    { "id": 3, "tasks": ["4.2", "5.1"] },
    { "id": 4, "tasks": ["5.2", "6.1"] },
    { "id": 5, "tasks": ["6.2", "6.3", "6.4"] },
    { "id": 6, "tasks": ["7.1"] },
    { "id": 7, "tasks": ["7.2", "8.1"] },
    { "id": 8, "tasks": ["8.2", "8.3", "8.4"] },
    { "id": 9, "tasks": ["10.1"] },
    { "id": 10, "tasks": ["10.2", "10.3", "10.4", "10.5"] }
  ]
}
```
