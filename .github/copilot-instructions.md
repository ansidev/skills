# Copilot instructions

## Repository purpose and architecture

This repository is a curated collection of agent skills. Each local skill lives
under `skills/<skill-name>/SKILL.md` and is installed through the GitHub CLI
skill system.

`Taskfile.yaml` is the automation entry point:

- `install-all-local-skills` installs every skill in this repository with
  `gh skill install . --all --from-local ...`.
- `install-selected-skills-from-repo` installs named skills from external
  repositories.
- `install-all-skills-from-repo` installs all skills from an external
  repository.
- `link-one-skill-to-many-agents` and its child task create links from the
  universal skill directory (`$HOME/.agents/skills`) into agent-specific
  directories.
- `install` runs the local and external installations sequentially;
  `install-parallel` uses Task dependencies to run independent installation
  groups in parallel.

The `SKILLS_METADATA` variable is the source of truth for external skill
repositories and selected skill paths. The `DEFAULT_AGENTS` and `SKILL_DIRS`
variables define supported agent names and their user-level skill locations.

The repository intentionally keeps public/external skills out of version
control through `.gitignore`; only the local skills maintained here should be
edited directly. Skills imported from other repositories are installed by the
Taskfile and then linked for supported agents.

## Commands

Run `task -l` to list available tasks and descriptions.

Common workflows:

```sh
# Optional Homebrew/gh preparation
task prepare

# Install local and external skills sequentially
task -s install

# Install independent skill groups in parallel
task -s install-parallel

# Restrict linking/installation to selected agents
task -s install AGENTS=github-copilot
```

The Taskfile expects the GitHub CLI and the `gh skill` command. External
repository installation uses upstream sources and force-updates existing
installations; local installation uses `--from-local`.

There are currently no checked-in Bats test files, but the test support is
organized for Bats under `tests/`. When Bats tests exist, run the full suite
with:

```sh
bats tests/
```

Run one test file with:

```sh
bats tests/path/to/test.bats
```

No separate build or lint command is defined in the repository. For a
Taskfile-only syntax/command expansion check, use a dry run such as:

```sh
task --dry install
```

## Repository-specific conventions

- Keep each skill self-contained in `skills/<name>/SKILL.md` with YAML
  frontmatter followed by Markdown instructions. Preserve the existing
  frontmatter keys and naming style when editing a skill.
- Treat `Taskfile.yaml` as the canonical automation configuration. Add or
  change installation behavior there rather than introducing parallel shell
  scripts or Make targets.
- Use comma-separated `AGENTS` values when overriding the default agent list.
  Agent names must match the keys in `SKILL_DIRS`; unknown names do not have a
  configured destination.
- Keep universal skill installation separate from agent-specific linking:
  install into `$HOME/.agents/skills` first, then link into agent directories.
- Preserve the distinction between wildcard external repositories (`skills:
  '*'`) and explicitly selected skill paths. Wildcards use the all-skills
  installation path; named entries are installed one at a time.
- Follow the existing shell safety/error style in Taskfile recipes: check
  external command failures explicitly and emit an error before exiting.
- Bats helpers in `tests/helpers/common.bash` provide per-test temporary
  directories, PATH-based command stubs, call logs, output assertions, and
  symlink assertions. Reuse these helpers rather than invoking real `gh` or
  `brew` in tests.
- Keep generated skill directories, temporary test artifacts, and macOS
  `.DS_Store` files untracked according to `.gitignore`.
- README guidance is intentionally brief; use `Taskfile.yaml` and its task
  descriptions as the authoritative source when documenting or changing
  workflows.
