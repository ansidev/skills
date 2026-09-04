# Design Document: Makefile Skill Installer

## Overview

The Makefile skill installer is a pure GNU Make automation tool that installs Kiro skills across machines. It leverages the GitHub CLI (`gh extension install`) to install skills to the universal agent and uses POSIX symlinks (`ln -sf`) to link universal-agent skill directories into each named agent's skill directory.

All logic lives inside a single `Makefile` — no external shell scripts, no Python helpers. Complex multi-step recipes use line-continuation (`\`) to keep all shell logic within Make's recipe syntax. The `.ONESHELL` special target is **not** used because it is unavailable on macOS's system Make (GNU Make 3.81); instead, each recipe line that needs state to carry forward joins commands with `&&` or uses `\` continuation.

### Key Workflows

```
make                  → help (default target)
make prepare          → install gh CLI via Homebrew if missing
make install repo=X   → install skills from repo X
make install-all      → read skills.txt, invoke install for each line
```

### Research Findings

- **GNU Make variable indirection** is the idiomatic way to implement a key-value map: define variables named `skill_dir_<agent>` and look them up with `$(skill_dir_$(agent))`. This avoids any external tools and works in all GNU Make versions.
- **No-trailing-newline handling**: The standard shell idiom `while IFS= read -r line || [ -n "$$line" ]` correctly processes the final line of a file whether or not it ends with `\n`.
- **Comma-separated splitting in shell**: `IFS=, read -ra arr <<< "$$val"` (bash) or `echo "$$val" | tr ',' '\n'` (POSIX sh) splits on commas. Since the Makefile is targeted at macOS/Linux with bash available, `IFS` splitting inside recipes is reliable.
- **Continuing on sub-make failure**: Using `$(MAKE) install ... ; status=$$?` inside a loop, collecting failures, then checking at the end lets install-all continue after any single entry fails.
- **Debug propagation**: Passing `debug=$(debug)` to every `$(MAKE) install` call ensures the flag is inherited by sub-invocations.

---

## Architecture

The system is a single file (`Makefile`) with four public targets and a set of internal variables.

```
┌─────────────────────────────────────────────────┐
│                    Makefile                     │
│                                                 │
│  Global Variables                               │
│  ─────────────────                              │
│  agents    (default: pi,codex,opencode)         │
│  scope     (default: user)                      │
│  debug     (default: false)                     │
│  skill_dir_<agent> × 5  (key-value map)         │
│                                                 │
│  Public Targets          Dependencies           │
│  ──────────────          ────────────           │
│  help  ◄──────────────── .DEFAULT_GOAL          │
│  prepare                                        │
│  install ◄─────────────── install-all           │
│  install-all                                    │
└─────────────────────────────────────────────────┘
```

### Data Flow: `make install`

```
 CLI args (repo, skills, agents, scope, debug)
            │
            ▼
  ┌─────────────────┐
  │ Input validation │  repo absent → stderr + exit 1
  └────────┬────────┘
           │ valid
           ▼
  ┌─────────────────────────┐
  │ Default resolution       │  agents → pi,codex,opencode
  │                          │  skills → *
  │                          │  scope  → user
  │                          │  debug  → false
  └────────┬────────────────┘
           │
           ▼
  ┌─────────────────────────┐
  │ agent_arr construction   │  split on comma, trim whitespace,
  │                          │  ensure universal is present
  └────────┬────────────────┘
           │
    ┌──────┴──────────────┐
    │ skills == "*"?       │
    │  Yes       No        │
    ▼            ▼
 wildcard    named-skill
 install      loop
    │            │
    │       for each skill:
    │         gh install → universal
    │         for each agent in agent_arr:
    │           lookup skill_dir_<agent>
    │           ln -sf  ~/.agents/skills/<skill>  <dir>/<skill>
    │           (or warn if agent not in map)
    └──────┬──────────────┘
           ▼
  unrecognized-agent warning (stderr, exit 0)
```

### Data Flow: `make install-all`

```
  skills.txt exists?  No → stderr + exit 1
        │ Yes
        ▼
  for each line (IFS= read -r line || [ -n "$$line" ]):
    skip blank lines
    contains "|"?  No → warn + skip
        │ Yes
        ▼
    split on first "|" → repo, skills
    $(MAKE) install repo=$$repo skills=$$skills agents=$(agents) scope=user debug=$(debug)
    record failure if exit != 0
        │
        ▼
  all done:
    failures? → print failure summary, exit 1
    all ok    → print success summary, exit 0
```

---

## Components and Interfaces

### 1. Global Variable Block

Declared near the top of the Makefile with `?=` (allow override from command line or environment):

| Variable | Type | Default | Notes |
|---|---|---|---|
| `agents` | string (comma-list) | `pi,codex,opencode` | Caller-overridable |
| `scope` | string (enum) | `user` | `user` or `project` |
| `debug` | string (bool-like) | `false` | `true` or `false` |

The `?=` assignment means the variable is only set if it is not already in the environment or on the command line, fulfilling requirements 2.3 and 2.4.

Requirement 2.5 (empty `agents` treated as default) is handled inside the `install` recipe via a shell conditional:

```make
agents_resolved="$(agents)"; \
[ -z "$$agents_resolved" ] && agents_resolved="$(DEFAULT_AGENTS)"; \
```

### 2. Agent Skill Directory Map

GNU Make has no native map type. The design uses **variable indirection**: one Make variable per agent, all prefixed `skill_dir_`:

```make
skill_dir_claude-code  := $(HOME)/.claude/skills
skill_dir_codex        := $(HOME)/.codex/skills/
skill_dir_opencode     := $(HOME)/.config/opencode/skills
skill_dir_pi           := $(HOME)/.pi/agent/skills
skill_dir_github-copilot := $(HOME)/.copilot/skills
```

Lookup inside a shell recipe:

```bash
# agent is a shell variable holding e.g. "codex"
skill_dir=$(SKILL_DIR_$(agent))   # NOT VALID — mixing Make/shell is the trap
```

The correct approach: because `$(skill_dir_$(agent))` requires a runtime shell value as the key, Make's static expansion won't work directly. Instead, export all mappings as environment variables and look them up in the shell:

```make
export SKILL_DIR_claude__code  := $(HOME)/.claude/skills
export SKILL_DIR_codex         := $(HOME)/.codex/skills/
export SKILL_DIR_opencode      := $(HOME)/.config/opencode/skills
export SKILL_DIR_pi            := $(HOME)/.pi/agent/skills
export SKILL_DIR_github__copilot := $(HOME)/.copilot/skills
```

Because environment variable names cannot contain `-`, hyphens in agent names are replaced with `__` (double underscore) in the variable name. The recipe normalizes the agent name before lookup:

```bash
agent_key=$$(echo "$$agent" | tr '-' '_' | tr '-' '_')
# double underscore for hyphen:
agent_key=$$(echo "$$agent" | sed 's/-/__/g')
eval skill_dir="\$$SKILL_DIR_$$agent_key"
```

Alternatively — and more portably — the lookup can be implemented as a shell `case` statement inside the recipe, which avoids the hyphen-substitution complexity entirely and is easier to maintain:

```bash
case "$$agent" in
  claude-code)     skill_dir="$$HOME/.claude/skills" ;;
  codex)           skill_dir="$$HOME/.codex/skills/" ;;
  opencode)        skill_dir="$$HOME/.config/opencode/skills" ;;
  pi)              skill_dir="$$HOME/.pi/agent/skills" ;;
  github-copilot)  skill_dir="$$HOME/.copilot/skills" ;;
  *)               skill_dir="" ;;
esac
```

**Design decision**: Use the `case` statement approach. It is more readable, avoids environment variable naming complications, and is fully self-contained within the recipe. The five entries are small enough that a `case` is not burdensome to maintain. The Make-level `skill_dir_*` variables still exist as the authoritative declarations (satisfying Req 3.1 read-only semantics), but the recipe uses a shell `case` derived from them for actual lookup.

### 3. `help` Target

Prints a formatted table of targets and a variable summary. Implementation uses `@echo` lines with consistent formatting. Registered as `.DEFAULT_GOAL`:

```make
.DEFAULT_GOAL := help
```

### 4. `prepare` Target

Uses `command -v` (POSIX) or `which` to probe for `brew` and `gh`. Conditional logic implemented with shell `if`/`fi` inside the recipe.

### 5. `install` Target

Parameters (all passed as Make variables on the command line):

| Parameter | Required | Default |
|---|---|---|
| `repo` | Yes | — |
| `skills` | No | `*` |
| `agents` | No | `pi,codex,opencode` |
| `scope` | No | `user` |
| `debug` | No | `false` |

The recipe is a single long shell block joined with `\` continuations, so all variables remain in scope. Execution order:

1. Validate `repo` non-empty.
2. Validate `scope` ∈ {user, project}.
3. Resolve defaults for `skills`, `agents`, `debug`.
4. Build `agent_arr` from comma-split of `agents`, appending `universal` if absent.
5. Branch on `skills == "*"` (wildcard) vs. named list.

### 6. `install-all` Target

Reads `skills.txt` with:

```bash
while IFS= read -r line || [ -n "$$line" ]; do
```

The `|| [ -n "$$line" ]` clause handles files with no trailing newline. Blank lines and lines without `|` are skipped with a warning. Each valid line invokes `$(MAKE) install` and captures the exit status; failures are accumulated in a list.

---

## Data Models

### `skills.txt` Format

```
<repo>|<skills>
```

- `repo`: GitHub repository identifier, format `<owner>/<repo-name>`.
- `skills`: Comma-delimited list of skill names, or `*` for all skills.
- Lines starting with `#` or blank lines are skipped.
- The `|` is the delimiter; text before the first `|` is `repo`, text after is `skills`.

Examples:

```
ansidev/kiro|*
anthropics/skills|skill-creator,researcher
```

### Agent Directory Map (Logical Model)

| Agent key | Directory |
|---|---|
| `claude-code` | `$HOME/.claude/skills` |
| `codex` | `$HOME/.codex/skills/` |
| `opencode` | `$HOME/.config/opencode/skills` |
| `pi` | `$HOME/.pi/agent/skills` |
| `github-copilot` | `$HOME/.copilot/skills` |

### Symlink Structure

Universal install places skills under `~/.agents/skills/<skill>`. Named-skill symlinks point into each agent's directory:

```
~/.agents/skills/<skill>          ← installed by gh extension install (universal)
    ↑ ln -sf
<agent_skill_dir>/<skill>         ← symlink per named agent
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Caller-supplied `agents` is used verbatim

*For any* non-empty, non-whitespace comma-delimited agents string supplied on the command line, the resolved `agent_arr` SHALL contain exactly the tokens from that string (trimmed of surrounding whitespace), plus `universal` appended if not already present.

**Validates: Requirements 2.3, 7.1, 7.2, 7.3**

---

### Property 2: Invalid `scope` values are always rejected

*For any* string that is neither `"user"` nor `"project"`, invoking any target with `scope=<string>` SHALL produce output on stderr, exit with a non-zero code, and execute no install commands.

**Validates: Requirements 2.6**

---

### Property 3: `agent_arr` always contains `universal` exactly once

*For any* comma-delimited agents string (including empty, whitespace-only, already containing `universal`, or not containing `universal`), the resolved `agent_arr` SHALL contain the string `"universal"` exactly once.

**Validates: Requirements 7.2, 7.3, 7.4**

---

### Property 4: Wildcard install runs exactly one `gh` command targeting `universal`

*For any* non-empty `repo` and any valid `scope`, when `skills` resolves to `*`, the `install` target SHALL invoke exactly one `gh extension install` command that includes `--all`, `--agent universal`, the given `repo`, and the given `scope`.

**Validates: Requirements 8.1**

---

### Property 5: Named-skill install runs one `gh` universal install per skill

*For any* non-empty `repo`, any valid `scope`, and any non-empty comma-delimited `skills` list, the `install` target SHALL invoke exactly one `gh extension install` command per skill (targeting `universal`) and no more.

**Validates: Requirements 9.1, 9.2**

---

### Property 6: Symlinks are created for every recognized agent in `agent_arr`

*For any* non-empty skill name and any `agent_arr` where each agent is present in the directory map, the `install` target SHALL create (or update) a symlink at `<agent_skill_dir>/<skill>` pointing to `~/.agents/skills/<skill>` for every agent.

**Validates: Requirements 9.3**

---

### Property 7: Unrecognized agents are warned about, but do not cause failure

*For any* invocation of `install` with a named skills list where `agent_arr` contains one or more agent names absent from the directory map, the target SHALL exit with code 0, SHALL print a warning summary to stderr listing every unrecognized agent name exactly once, and SHALL still complete all recognized-agent symlinks.

**Validates: Requirements 10.1, 10.2, 10.4**

---

### Property 8: `install-all` processes every valid line in `skills.txt`

*For any* `skills.txt` content (including files with no trailing newline, blank lines, and comment lines) containing N valid `repo|skills` lines, the `install-all` target SHALL invoke `$(MAKE) install` exactly N times — once per valid line — regardless of how many of those invocations fail.

**Validates: Requirements 12.1, 12.2, 12.3, 12.4, 13.1**

---

### Property 9: `install-all` failure summary is complete and accurate

*For any* `skills.txt` where a subset of entries fail, the `install-all` target SHALL print a failure summary that lists the `repo` and `skills` of every failed entry, exit with a non-zero code, and omit any entry that succeeded.

**Validates: Requirements 13.1, 13.2, 13.3**

---

### Property 10: `debug=true` propagates to all sub-makes

*For any* `install-all` invocation with `debug=true`, every `$(MAKE) install` sub-invocation SHALL receive `debug=true` as an explicit argument.

**Validates: Requirements 13.5, 14.3**

---

### Property 11: Agent directory map paths expand `$HOME`

*For each* of the five agents in the directory map (`claude-code`, `codex`, `opencode`, `pi`, `github-copilot`), the resolved skill directory path SHALL begin with the actual value of `$HOME` (not the literal string `$HOME`).

**Validates: Requirements 3.2**

---

## Error Handling

### Pattern: Print to stderr, exit non-zero

All fatal errors follow this pattern inside a recipe:

```bash
echo "Error: <message>" >&2; exit 1
```

### Error Catalog

| Situation | Output | Exit code |
|---|---|---|
| `repo` absent or empty | stderr: usage message with parameter descriptions and defaults | 1 |
| `scope` not `user`/`project` | stderr: "Invalid scope: <value>. Must be 'user' or 'project'." | 1 |
| `skills.txt` not found | stderr: "Error: skills.txt not found in current directory." | 1 |
| Malformed `skills.txt` line | stderr: "Warning: skipping malformed line: <line>" | 0 (continues) |
| `brew trust` exits non-zero | stderr: "Error: brew trust failed." | 1 |
| `brew install gh` exits non-zero | stderr: "Error: brew install gh failed." | 1 |
| Agent not in directory map | stderr (at end): "Warning: unrecognized agent(s): <name1>, <name2>" | 0 |
| One or more `$(MAKE) install` failures in `install-all` | stdout (at end): failure summary listing each failed `repo|skills` | 1 |

### Non-Fatal Continuations

- `install-all` uses `$(MAKE) install ...; rc=$$?` and accumulates failures, continuing the loop regardless.
- Unrecognized agents during named-skill install are recorded and reported at the end without stopping the loop.

### `prepare` Error Tolerance

If `brew` is absent, both `brew trust` and `brew install gh` are silently skipped (exit 0). This allows the Makefile to be used on systems where Homebrew is not available and `gh` was installed via another mechanism.

---

## Testing Strategy

### Assessment: Is Property-Based Testing (PBT) Appropriate?

This feature is a GNU Make automation tool. The _pure-logic layer_ — argument parsing, agent array construction, manifest line parsing, failure accumulation — lives inside shell recipes and can be tested as shell functions. PBT is appropriate for these pure logic layers.

The _side-effect layer_ — actual `gh extension install` invocations, `ln -sf` symlink creation, `brew` commands — requires mocking and is tested with example-based integration tests using stub scripts on `PATH`.

### Testing Approach

**Unit/Shell Function Tests (Bats or plain sh)**

Extract pure logic helpers into testable shell functions (or inline them and invoke via `make` with mocked externals):

1. `agent_arr` construction: given a comma-string, verify correct array with `universal`.
2. Scope validation: given invalid scope, verify error and exit 1.
3. `skills.txt` line parser: given various line formats, verify correct `repo`/`skills` split or skip.

**Integration Tests (Makefile invocations with PATH-stubbed tools)**

Create minimal stub scripts (`gh`, `brew`) in a temp directory prepended to `PATH`. Each test:

1. Sets up the environment (temp dir, stub scripts, optional `skills.txt`).
2. Invokes `make <target> [vars]`.
3. Asserts exit code, stdout content, stderr content, and/or files created.

**Property-Based Tests**

Use [Bats](https://github.com/bats-core/bats-core) with a property-test helper, or a lightweight shell-based generator. Each test generates N random inputs and asserts the property holds for each.

Property tests map to design properties as follows:

| Property | Test technique | Iterations |
|---|---|---|
| P1: Caller agents used verbatim | Generate random comma-lists → check agent_arr | 100 |
| P2: Invalid scope rejected | Generate random strings ∉ {user,project} → check exit 1 | 100 |
| P3: `universal` always in agent_arr exactly once | Generate lists with/without universal → check count | 100 |
| P4: Wildcard runs exactly one `gh --all` command | Generate random repo/scope → check stub `gh` call log | 100 |
| P5: Named-skill runs one `gh` per skill | Generate random skill lists → check call log | 100 |
| P6: Symlinks created for recognized agents | Generate agent subsets from map → check symlinks | 100 |
| P7: Unrecognized agents warn, exit 0 | Generate agent lists with unknown names → check stderr, exit | 100 |
| P8: install-all processes all valid lines | Generate random skills.txt → check invoke count | 100 |
| P9: install-all failure summary complete | Generate partial-fail scenarios → check summary | 100 |
| P10: debug propagates to sub-makes | Inspect sub-make args in install-all with debug=true | 100 |
| P11: $HOME expanded in map paths | Check each of 5 agents; $HOME substituted | 5 (exhaustive) |

**Tag format for each property test:**

```bash
# Feature: makefile-skill-installer, Property N: <property text>
```

### Unit vs. Property Balance

- Property tests cover universal correctness across the input space.
- Example-based tests cover specific error messages, exact help output formatting, and `prepare` behavior with mocked `brew`/`gh`.
- Avoid writing both a property test and an example test for the same acceptance criterion — the property test subsumes the examples.
