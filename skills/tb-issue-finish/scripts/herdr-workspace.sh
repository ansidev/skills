#!/bin/zsh

# Workspace management functions

# Create new herdr workspace
function ws-new() {
  local WORKSPACE_DIR="${1:-$PWD}"
  herdr workspace create --cwd "${WORKSPACE_DIR}" ${@:2}
}

# List herdr workspace
function ws-list() {
  herdr workspace list | jq -r '
  .result.workspaces
  | (["#", "Label", "Status", "Focused", "Panes", "Tabs", "Workspace ID"],
     (.[] | [.number, .label, .agent_status, .focused, .pane_count, .tab_count, .workspace_id]))
  | @tsv
' | column -t -s '	'
}

# Open herdr workspace
function ws-open() {
  local WORKSPACE_DIR="${1:-$PWD}"
  herdr workspace create --cwd "${WORKSPACE_DIR}" --focus
}

# Close herdr workspace
function ws-close() {
  local workspace_id

  workspace_id=$(herdr workspace list |
    jq -r --arg value "$1" '
      .result.workspaces[]
      | select(.label == $value or .workspace_id == $value)
      | .workspace_id
    ')

  if [[ -z "$workspace_id" ]]; then
    echo "Workspace not found: $1" >&2
    return 1
  fi

  herdr workspace close "$workspace_id"
}


# Worktree management functions

# Get worktree directory associated with a git branch
wt-dir() {
  local BRANCH=$1
  git worktree list --porcelain |
    awk -v branch="refs/heads/$BRANCH" '
      /^worktree / { dir= substr($0, 10) }
      /^branch / && $2 == branch { print dir }
    '
}

# Clean up the git worktree, branch and herdr workspace, usually used on task completion
function wt-delete() {
  CURRENT_DIR=$(basename ${PWD})
  REPO=${2:-"${CURRENT_DIR}"}
  BRANCH=$1
  WORKTREE_DIR=$(wt-dir $BRANCH)

  echo "============================="
  echo "REPO: $REPO"
  echo "BRANCH: $BRANCH"
  echo "WORKTREE_DIR: $WORKTREE_DIR"
  echo "============================="

  if [[ -n "${WORKTREE_DIR}" ]]; then
    echo "Removing worktree"
    git worktree remove --force "${WORKTREE_DIR}" &>/dev/null || echo "Worktree ${WORKTREE_DIR} does not exist or has already been removed."
  else
    echo "Worktree for branch $BRANCH does not exist. Skip deletion."
  fi

  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Removing branch $BRANCH..."
    git branch -D "$BRANCH"
  else
    echo "Branch $BRANCH does not exist. Skip deletion."
  fi

  if [[ -n "${WORKTREE_DIR}" ]]; then
    echo "Removing worktree directory $WORKTREE_DIR..."
    rm -rf $WORKTREE_DIR
  else
    echo "Worktree directory $WORKTREE_DIR does not exist. Skip deletion."
  fi

  (echo "Closing herdr workspace $BRANCH..." && ws-close $1)
  echo "Repo ${REPO} - Worktree $BRANCH deleted."
}
