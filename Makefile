# =============================================================================
# Makefile — Agent Skill Installer
# =============================================================================
# Installs agent skills across machines using the GitHub CLI (gh).
#
# Usage:
#   make                          → show help (default)
#   make prepare                  → install gh CLI via Homebrew if missing
#   make install repo=<R>         → install skills from repo <R>
#   make install-all              → read skills.txt and install all entries
#
# Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6
# =============================================================================

# ---------------------------------------------------------------------------
# Global variables (overridable from the command line or environment)
# ---------------------------------------------------------------------------

## agents — comma-delimited list of agent names to install skills to
agents ?= pi,opencode,codex,claude-code,github-copilot,kiro-cli

## scope  — gh skill install scope; must be 'user' or 'project'
scope ?= user

## debug  — print expanded commands instead of executing them; 'true' or 'false'
debug ?= false

# Internal constant — used when resolving empty agents
DEFAULT_AGENTS := pi,opencode,codex,claude-code,github-copilot,kiro-cli

# ---------------------------------------------------------------------------
# Agent skill directory resolver (Req 3.1, 3.2, 3.3)
#
# Usage inside a recipe (agent is a shell variable):
#   $(RESOLVE_AGENT_DIR)
# After expansion, the shell variable `skill_dir` holds the resolved path,
# or an empty string if the agent is not in the map.
# ---------------------------------------------------------------------------

define RESOLVE_AGENT_DIR
case "$$agent" in \
  claude-code)     skill_dir="$$HOME/.claude/skills" ;; \
  codex)           skill_dir="$$HOME/.codex/skills" ;; \
  github-copilot)  skill_dir="$$HOME/.copilot/skills" ;; \
  kiro-cli)        skill_dir="$$HOME/.kiro/skills" ;; \
  opencode)        skill_dir="$$HOME/.config/opencode/skills" ;; \
  pi)              skill_dir="$$HOME/.pi/agent/skills" ;; \
  *)               skill_dir="" ;; \
esac ;
endef

# ---------------------------------------------------------------------------
# Default goal
# ---------------------------------------------------------------------------

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Phony declarations
# ---------------------------------------------------------------------------

.PHONY: help prepare install install-all

# ---------------------------------------------------------------------------
# help target (Req 1.1, 1.2, 1.3)
# ---------------------------------------------------------------------------

help:
	@echo "Agent Skill Installer"
	@echo ""
	@echo "Targets:"
	@echo "  help         Show this help message and exit"
	@echo "  prepare      Install the GitHub CLI (gh) via Homebrew when missing"
	@echo "  install      Install skills from a GitHub repo to one or more agents"
	@echo "  install-all  Read skills.txt and install every declared repo/skill entry"
	@echo ""
	@echo "Global variables:"
	@echo "  agents  list    pi,codex,opencode   Comma-delimited agent names"
	@echo "  scope   string  user                Installation scope: 'user' or 'project'"
	@echo "  debug   string  false               Print expanded commands: 'true' or 'false'"

# ---------------------------------------------------------------------------
# prepare target (Req 4.1–4.7)
# ---------------------------------------------------------------------------

prepare:
	@if ! command -v brew > /dev/null 2>&1; then \
	  exit 0; \
	fi; \
	brew trust /opt/homebrew; \
	if [ $$? -ne 0 ]; then \
	  echo "Error: brew trust failed." >&2; exit 1; \
	fi; \
	if ! command -v gh > /dev/null 2>&1; then \
	  brew install gh; \
	  if [ $$? -ne 0 ]; then \
	    echo "Error: brew install gh failed." >&2; exit 1; \
	  fi; \
	fi; \
	echo "prepare: done."

# ---------------------------------------------------------------------------
# install target (Req 5–10, 14)
# ---------------------------------------------------------------------------

install:
	@repo_val="$(repo)"; \
	\
	if [ -z "$$repo_val" ]; then \
	  echo "Usage: make install repo=<repo> [skills=*] [agents=pi,codex,opencode] [scope=user] [debug=false]" >&2; \
	  echo "Error: 'repo' is required." >&2; \
	  exit 1; \
	fi; \
	\
	scope_val="$(scope)"; \
	if [ "$$scope_val" != "user" ] && [ "$$scope_val" != "project" ]; then \
	  echo "Error: Invalid scope: '$$scope_val'. Must be 'user' or 'project'." >&2; \
	  exit 1; \
	fi; \
	\
	skills_input="$(skills)"; \
	if [ -z "$$skills_input" ]; then \
	  skills_resolved="*"; \
	else \
	  skills_resolved="$$skills_input"; \
	fi; \
	\
	debug_input="$(debug)"; \
	if [ "$$debug_input" = "true" ] || [ "$$debug_input" = "false" ]; then \
	  debug_resolved="$$debug_input"; \
	else \
	  debug_resolved="false"; \
	fi; \
	\
	agents_input="$(agents)"; \
	agents_trimmed=$$(echo "$$agents_input" | tr -d ' \t'); \
	if [ -z "$$agents_trimmed" ]; then \
	  agents_resolved="universal"; \
	else \
	  agents_resolved="$$agents_input"; \
	fi; \
	\
	agent_list=""; \
	has_universal=0; \
	old_IFS="$$IFS"; \
	IFS=','; \
	for raw_agent in $$agents_resolved; do \
	  IFS="$$old_IFS"; \
	  token=$$(echo "$$raw_agent" | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	  if [ -z "$$token" ]; then \
	    IFS=','; \
	    continue; \
	  fi; \
	  if [ "$$token" = "universal" ]; then \
	    has_universal=1; \
	  fi; \
	  if [ -z "$$agent_list" ]; then \
	    agent_list="$$token"; \
	  else \
	    agent_list="$$agent_list $$token"; \
	  fi; \
	  IFS=','; \
	done; \
	IFS="$$old_IFS"; \
	if [ -z "$$agent_list" ]; then \
	  agent_list="universal"; \
	  has_universal=1; \
	fi; \
	if [ "$$has_universal" = "0" ]; then \
	  agent_list="$$agent_list universal"; \
	fi; \
	\
	if [ "$$skills_resolved" = "*" ]; then \
	  cmd="gh skill install \"$$repo_val\" --all --upstream --force --scope \"$$scope_val\" --agent universal"; \
	  if [ "$$debug_resolved" = "true" ]; then \
	    echo "$$cmd"; \
	  else \
	    echo "Installing all skills from $$repo_val (scope: $$scope_val, agent: universal)"; \
	    eval "$$cmd"; \
	  fi; \
	else \
	  unrecognized_agents=""; \
	  old_IFS2="$$IFS"; \
	  IFS=','; \
	  for raw_skill in $$skills_resolved; do \
	    IFS="$$old_IFS2"; \
	    skill=$$(echo "$$raw_skill" | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	    if [ -z "$$skill" ]; then \
	      IFS=','; \
	      continue; \
	    fi; \
	    gh_cmd="gh skill install \"$$repo_val\" \"$$skill\" --upstream --force --scope \"$$scope_val\" --agent universal"; \
	    if [ "$$debug_resolved" = "true" ]; then \
	      echo "$$gh_cmd"; \
	    else \
	      echo "Installing skill: $$skill from $$repo_val (scope: $$scope_val, agent: universal)"; \
	      eval "$$gh_cmd"; \
	    fi; \
	    for agent in $$agent_list; do \
	      if [ "$$agent" = "universal" ]; then \
	        IFS=','; \
	        continue; \
	      fi; \
	      $(RESOLVE_AGENT_DIR) \
	      if [ -z "$$skill_dir" ]; then \
	        already=0; \
	        for ua in $$unrecognized_agents; do \
	          if [ "$$ua" = "$$agent" ]; then already=1; fi; \
	        done; \
	        if [ "$$already" = "0" ]; then \
	          if [ -z "$$unrecognized_agents" ]; then \
	            unrecognized_agents="$$agent"; \
	          else \
	            unrecognized_agents="$$unrecognized_agents $$agent"; \
	          fi; \
	        fi; \
	      else \
	        ln_cmd="ln -sf $$HOME/.agents/skills/$$skill \"$$skill_dir\""; \
	        if [ "$$debug_resolved" = "true" ]; then \
	          echo "$$ln_cmd"; \
	        else \
	          echo "  -> Linking $$skill to $$agent ($$skill_dir/$$skill)"; \
	          eval "$$ln_cmd"; \
	        fi; \
	      fi; \
	    done; \
	    IFS=','; \
	  done; \
	  IFS="$$old_IFS2"; \
	  if [ -n "$$unrecognized_agents" ]; then \
	    echo "Warning: unrecognized agent(s): $$unrecognized_agents" >&2; \
	  fi; \
	  exit 0; \
	fi

# ---------------------------------------------------------------------------
# install-all target (Req 11–13)
# ---------------------------------------------------------------------------

install-all:
	@if [ ! -f skills.txt ]; then \
	  echo "Error: skills.txt not found in current directory." >&2; \
	  exit 1; \
	fi; \
	\
	failures=""; \
	\
	while IFS= read -r line || [ -n "$$line" ]; do \
	  trimmed=$$(echo "$$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	  if [ -z "$$trimmed" ]; then \
	    continue; \
	  fi; \
	  if ! echo "$$trimmed" | grep -q '|'; then \
	    echo "Warning: skipping malformed line: $$trimmed" >&2; \
	    continue; \
	  fi; \
	  repo_entry=$$(echo "$$trimmed" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	  skills_entry=$$(echo "$$trimmed" | cut -d'|' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	  $(MAKE) install repo="$$repo_entry" skills="$$skills_entry" agents=$(agents) scope=user debug=$(debug); \
	  rc=$$?; \
	  if [ "$$rc" != "0" ]; then \
	    failures="$$failures $$repo_entry|$$skills_entry"; \
	  fi; \
	done < skills.txt; \
	\
	if [ -n "$$failures" ]; then \
	  echo "Failed installs:"; \
	  for entry in $$failures; do \
	    echo "  $$entry"; \
	  done; \
	  exit 1; \
	else \
	  echo "install-all: all skills installed successfully."; \
	  exit 0; \
	fi
