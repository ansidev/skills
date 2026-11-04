# ansidev's skills

## Scope

When creating, updating, reading, or deleting skills in this repository, always narrow the scope to this repository first: edit files under `skills/<skill-name>/` (and related repo paths such as `Taskfile.yaml`) rather than global skill directories like `~/.pi/agent/skills/`, `~/.agents/skills/`, or agent-specific skill directories.

## Layout

- `skills/<skill-name>/SKILL.md` — each local skill, self-contained with YAML frontmatter followed by Markdown instructions.
- `Taskfile.yaml` — canonical automation entry point (install, install-parallel, linking tasks). Authoritative source of truth for workflows.
- `tests/` — Bats test support (`tests/helpers/common.bash`), currently no checked-in test files.
- `.github/copilot-instructions.md` — detailed repository architecture and conventions.

## Commands

- `task -l` — list available tasks.
- `task -s install` — sequential install (local + external).
- `task -s install-parallel` — parallel install.
- `task --dry install` — dry-run for Taskfile syntax/command expansion.
- `bats tests/` — run Bats tests when present.
- Restrict agents: `task -s install AGENTS=github-copilot` (comma-separated, must match `SKILL_DIRS` keys).

## Conventions

- Treat `Taskfile.yaml` as canonical automation; change installation behavior there, not parallel scripts.
- Preserve existing skill frontmatter keys and naming style.
- Use comma-separated `AGENTS` values; unknown names have no configured destination.
- Keep universal (`$HOME/.agents/skills`) install separate from agent-specific linking.
- Keep `.DS_Store`, temp artifacts, and generated skill dirs untracked per `.gitignore`.
- No build or lint command defined; use Taskfile dry run for validation.
