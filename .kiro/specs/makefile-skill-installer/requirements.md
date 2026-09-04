# Requirements Document

## Introduction

This document defines requirements for a Makefile automation feature that installs Kiro skills across machines. The Makefile provides targets to prepare the environment, install all skills declared in a manifest file, and install individual skills from GitHub repositories to one or more agents. It is designed for repeatability across machines and CI environments.

## Glossary

- **Makefile**: The GNU make build file containing the automation targets described in this document.
- **Target**: A named rule in the Makefile that can be invoked via `make <target>`.
- **skills.txt**: A manifest file in the current working directory listing skill repos and skill names, one per line, using the format `<repo>|<skills>`.
- **Repo**: A GitHub repository identifier in the form `<owner>/<repo-name>` from which a skill is installed.
- **Skill**: A named skill within a repo. The wildcard `*` means all skills in the repo.
- **Agent**: A named agent identifier to which a skill is installed (e.g., `universal`, `pi`, `codex`, `opencode`).
- **Scope**: The installation scope for `gh extension install`, either `user` or `project`.
- **agent_arr**: The resolved array of agents derived from the `agents` variable, always including `universal`.
- **GH_CLI**: The GitHub CLI tool (`gh`), required for all install operations.
- **Brew**: The Homebrew package manager used to install GH_CLI on macOS.
- **global_agent_skill_dir_map**: A Makefile variable that maps each supported agent name to its global skills directory path on the local filesystem. Used during named-skill installation to resolve the symlink target directory for each agent.

## Requirements

### Requirement 1: Help Target

**User Story:** As a developer, I want to run `make help` and see all available targets and their descriptions, so that I can discover how to use the Makefile without reading the source.

#### Acceptance Criteria

1. WHEN `make` is invoked with no arguments, THE Makefile SHALL execute the `help` target.
2. WHEN the `help` target is invoked, THE Makefile SHALL print to stdout the name and a one-line description of each available target (`prepare`, `install-all`, `install`, `help`).
3. WHEN the `help` target is invoked, THE Makefile SHALL print to stdout the name, kind (one of: `string`, `list`), and default value of each global variable (`agents`, `scope`).

---

### Requirement 2: Global Variables

**User Story:** As a developer, I want default values for `agents` and `scope` so that I do not need to specify them on every invocation.

#### Acceptance Criteria

1. THE Makefile SHALL define a global variable `agents` with the default value `pi,codex,opencode`.
2. THE Makefile SHALL define a global variable `scope` with the default value `user`.
3. WHERE a caller provides `agents` on the command line, THE Makefile SHALL use the caller-supplied value instead of the default for that invocation only.
4. WHERE a caller provides `scope` on the command line, THE Makefile SHALL use the caller-supplied value instead of the default for that invocation only.
5. IF a caller provides `agents` as an empty string, THEN THE Makefile SHALL treat it as if `agents` was not provided and use the default value.
6. IF a caller provides `scope` with a value other than `user` or `project`, THEN THE Makefile SHALL print an error message to stderr and exit with a non-zero exit code.

---

### Requirement 3: Global Agent Skill Directory Map

**User Story:** As a developer, I want a pre-defined mapping from each agent name to its global skills directory, so that the Makefile can resolve the correct symlink destination for each agent without requiring me to specify paths manually.

#### Acceptance Criteria

1. THE Makefile SHALL define a global variable `global_agent_skill_dir_map` containing exactly the following agent-to-directory mappings:
   - `claude-code` → `$HOME/.claude/skills`
   - `codex` → `$HOME/.codex/skills/`
   - `opencode` → `$HOME/.config/opencode/skills`
   - `pi` → `$HOME/.pi/agent/skills`
   - `github-copilot` → `$HOME/.copilot/skills`
2. THE Makefile SHALL evaluate all directory paths in `global_agent_skill_dir_map` with `$HOME` expanded to the invoking user's home directory at the time of invocation.
3. THE Makefile SHALL treat `global_agent_skill_dir_map` as read-only; no target SHALL modify the map at runtime.

---

### Requirement 4: Prepare Target

**User Story:** As a developer setting up a new machine, I want `make prepare` to install the GitHub CLI and configure Homebrew trust, so that subsequent install targets work without manual setup.

#### Acceptance Criteria

1. WHEN the `prepare` target is invoked, IF `brew` is present on `PATH`, THE Makefile SHALL run `brew trust /opt/homebrew`.
2. WHEN the `prepare` target is invoked, IF `gh` is not present on `PATH` and `brew` is present on `PATH`, THE Makefile SHALL run `brew install gh` to install GH_CLI.
3. WHEN the `prepare` target is invoked, IF `gh` is already present on `PATH`, THE Makefile SHALL skip the GH_CLI installation step.
4. WHEN the `prepare` target completes successfully, THE Makefile SHALL print a message to stdout indicating that preparation completed successfully.
5. IF `brew` is not present on `PATH`, THEN THE Makefile SHALL skip both the `brew trust` and `brew install gh` steps and exit with status code 0.
6. IF the `brew trust /opt/homebrew` command exits with a non-zero status, THEN THE Makefile SHALL print an error message to stderr and exit with a non-zero status code.
7. IF the `brew install gh` command exits with a non-zero status, THEN THE Makefile SHALL print an error message to stderr and exit with a non-zero status code.

---

### Requirement 5: install Target — Input Validation

**User Story:** As a developer, I want `make install` to validate required inputs before executing, so that I receive a clear error instead of a silent or confusing failure.

#### Acceptance Criteria

1. WHEN the `install` target is invoked with `repo` absent or set to an empty string, THE Makefile SHALL print a usage message to stderr that includes the `repo` parameter marked as required and each optional parameter together with its default value.
2. WHEN the `install` target is invoked with `repo` absent or set to an empty string, THE Makefile SHALL exit with a non-zero exit code without executing any install commands.
3. WHEN the `install` target is invoked with a non-empty `repo` value, THE Makefile SHALL execute the install commands and exit with code 0 on success.

---

### Requirement 6: install Target — Default Resolution

**User Story:** As a developer, I want optional parameters to fall back to sensible defaults when not supplied, so that common invocations are concise.

#### Acceptance Criteria

1. WHEN the `install` target is invoked without an `agents` value, THE Makefile SHALL resolve `agents` to the string literal `universal`.
2. WHEN the `install` target is invoked without a `skills` value, THE Makefile SHALL resolve `skills` to the string literal `*`.
3. WHEN the `install` target is invoked without a `scope` value, THE Makefile SHALL resolve `scope` to the string literal `user`.
4. WHEN the `install` target is invoked without a `debug` value, THE Makefile SHALL resolve `debug` to the string literal `false`.
5. WHEN the `install` target is invoked without any of `agents`, `skills`, `scope`, or `debug`, THE Makefile SHALL apply all four defaults simultaneously and proceed with installation.

---

### Requirement 7: install Target — Agent Array Resolution

**User Story:** As a developer, I want `universal` to always be included in the agent list so that skills are always installed to the universal agent regardless of what I pass.

#### Acceptance Criteria

1. WHEN the `install` target resolves the `agents` string, THE Makefile SHALL split the comma-delimited string into `agent_arr` where each element is a non-empty token trimmed of leading and trailing whitespace.
2. IF `universal` is not present as an exact, case-sensitive element of `agent_arr`, THEN THE Makefile SHALL append the string `universal` to `agent_arr` as the final element.
3. IF `universal` is already present as an exact, case-sensitive element of `agent_arr`, THEN THE Makefile SHALL leave `agent_arr` unchanged and not add a duplicate `universal` entry.
4. IF the `agents` string is empty or contains only whitespace and delimiters, THEN THE Makefile SHALL resolve `agent_arr` to a list containing exactly one element: `universal`.

---

### Requirement 8: install Target — Install All Skills (Wildcard)

**User Story:** As a developer, I want to install all skills from a repo with a single command when `skills` is `*`, so that I do not need to enumerate each skill name.

#### Acceptance Criteria

1. WHEN the `install` target is invoked and `skills` resolves to `*`, THE Makefile SHALL run exactly one command: `gh extension install --repo "$repo" --all --upstream --force --scope "$scope" --agent universal`.
2. WHEN `debug` is `true` and `skills` resolves to `*`, THE Makefile SHALL print the fully variable-expanded command that would be executed, without running it.
3. WHEN `debug` is `false` and `skills` resolves to `*`, THE Makefile SHALL print a one-line message containing the resolved values of `repo`, `scope`, and the agent name (`universal`).
4. IF `debug` is set to a value other than `true` or `false` and `skills` resolves to `*`, THEN THE Makefile SHALL treat `debug` as `false` and apply criterion 3 behavior.

---

### Requirement 9: install Target — Install Named Skills

**User Story:** As a developer, I want to install specific named skills from a repo to multiple agents using symlinks, so that I can control exactly which skills each agent receives without redundant downloads.

#### Acceptance Criteria

1. WHEN the `install` target is invoked and `skills` is a non-empty comma-delimited list of skill names, THE Makefile SHALL iterate over each skill name in the list and execute the per-skill installation steps defined in criteria 2 through 5.
2. WHILE iterating over a skill, THE Makefile SHALL run the universal install command: `gh extension install --repo "$repo" --upstream --force --scope "$scope" --agent universal`.
3. WHILE iterating over a skill, THE Makefile SHALL iterate over every agent in `agent_arr` and for each agent perform the following steps:
   a. Resolve `global_agent_skill_dir` by looking up the agent name as a key in `global_agent_skill_dir_map`.
   b. IF the agent key does not exist in `global_agent_skill_dir_map`, THEN THE Makefile SHALL skip the symlink step for that agent and record the agent name as unrecognized for end-of-target reporting.
   c. IF the agent key exists in `global_agent_skill_dir_map`, THEN THE Makefile SHALL run `ln -sf ~/.agents/skills/$skill <global_agent_skill_dir>/$skill` to create or update the symlink.
4. IF the `install` target is invoked and `skills` is empty or not provided, THEN THE Makefile SHALL exit with a non-zero status and print an error message indicating that at least one skill name is required.
5. WHEN `debug` is `true`, THE Makefile SHALL print each `gh extension install` command and each `ln` command in full before executing it.
6. WHEN `debug` is `false`, THE Makefile SHALL print one summary line per skill that includes the skill name and the list of agents to which it is being symlinked.

---

### Requirement 10: install Target — Unrecognized Agent Warnings

**User Story:** As a developer, I want to be informed when an agent I specified has no known skills directory, so that I can correct my agent list or update the map without the install silently skipping agents.

#### Acceptance Criteria

1. WHEN the `install` target iterates over `agent_arr` for a named skill and an agent name has no entry in `global_agent_skill_dir_map`, THE Makefile SHALL record that agent name as unrecognized.
2. WHEN the `install` target completes and one or more agents were recorded as unrecognized, THE Makefile SHALL print a warning summary to stderr that lists each unrecognized agent name exactly once.
3. WHEN the `install` target completes and no agents were recorded as unrecognized, THE Makefile SHALL omit the warning summary entirely.
4. THE Makefile SHALL exit with code 0 after the warning summary when all recognized-agent installs succeeded; unrecognized agents alone SHALL NOT cause a non-zero exit code.

---

### Requirement 11: install-all Target — Manifest Validation

**User Story:** As a developer, I want `make install-all` to fail early with a clear message when `skills.txt` is missing, so that I know exactly what to fix.

#### Acceptance Criteria

1. WHEN the `install-all` target is invoked and `skills.txt` does not exist in the current directory, THE Makefile SHALL print an error message to stderr that explicitly names the missing file (`skills.txt`).
2. WHEN the `install-all` target is invoked and `skills.txt` does not exist, THE Makefile SHALL exit with a non-zero exit code without attempting any installs.

---

### Requirement 12: install-all Target — Manifest Parsing

**User Story:** As a developer, I want `install-all` to read `skills.txt` and derive `repo` and `skills` from each line, so that I can declare all skills in one file and install them with a single command.

#### Acceptance Criteria

1. WHEN the `install-all` target reads `skills.txt`, THE Makefile SHALL process every non-empty line in the file.
2. WHEN the `install-all` target reads `skills.txt`, THE Makefile SHALL correctly handle files that do not end with a trailing newline by processing the last line as a valid entry.
3. WHEN the `install-all` target reads a line from `skills.txt`, THE Makefile SHALL split the line on the first `|` character and treat the text before `|` (trimmed of whitespace) as `repo` and the text after `|` (trimmed of whitespace) as `skills`.
4. WHEN the `install-all` target processes a parsed line, THE Makefile SHALL invoke `$(MAKE) install` with `repo=<repo>`, `skills=<skills>`, `agents=$(agents)`, and `scope=user`.
5. IF a line in `skills.txt` does not contain a `|` delimiter, THEN THE Makefile SHALL skip that line and print a warning message to stderr identifying the malformed line.

---

### Requirement 13: install-all Target — Error Handling and Reporting

**User Story:** As a developer, I want `install-all` to continue processing remaining skills when one fails, and then report all failures at the end, so that a single bad entry does not block the rest.

#### Acceptance Criteria

1. WHEN a `$(MAKE) install` invocation fails for a given line, THE Makefile SHALL continue processing all remaining lines without stopping.
2. WHEN the `install-all` target completes and one or more installs failed, THE Makefile SHALL print a failure summary to stdout that lists the `repo` and `skills` value of each entry that failed.
3. WHEN the `install-all` target completes and one or more installs failed, THE Makefile SHALL exit with a non-zero exit code.
4. WHEN the `install-all` target completes and all installs succeeded, THE Makefile SHALL print a success summary to stdout and exit with code 0.
5. WHEN `debug` is `true`, THE Makefile SHALL pass `debug=true` to each `$(MAKE) install` invocation.

---

### Requirement 14: Debug Mode

**User Story:** As a developer, I want a `debug` flag that prints the exact shell commands that would be run, so that I can verify or troubleshoot the Makefile without side effects.

#### Acceptance Criteria

1. THE Makefile SHALL accept a `debug` variable on any target invocation with values `true` or `false`.
2. WHEN `debug` is `true` on the `install` target, THE Makefile SHALL print each fully variable-expanded `gh extension install` command and each `ln` symlink command to stdout before executing it.
3. WHEN `debug` is `true` on the `install-all` target, THE Makefile SHALL propagate `debug=true` to all `$(MAKE) install` sub-invocations.
4. WHEN `debug` is `false`, THE Makefile SHALL suppress verbose command echoing and print only human-readable progress messages.
5. IF `debug` is set to a value other than `true` or `false`, THE Makefile SHALL treat it as `false` and apply criterion 4 behavior.
