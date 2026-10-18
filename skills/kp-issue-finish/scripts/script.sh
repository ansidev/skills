#!/bin/bash

# BEGIN OF FUNCTION DEFINITIONS
function ws-new() {
  local WORKSPACE_DIR="${1:-$PWD}"
  herdr workspace create --cwd "${WORKSPACE_DIR}" ${@:2}
}

function ws-list() {
  herdr workspace list | jq -r '
  .result.workspaces
  | (["#", "Label", "Status", "Focused", "Panes", "Tabs", "Workspace ID", "Worktree Path"],
     (.[] | [.number, .label, .agent_status, .focused, .pane_count, .tab_count, .workspace_id, .worktree.checkout_path]))
  | @tsv
' | column -t -s $'\t'
}

function ws-id() {
  local WORKSPACE_NAME=$1
  local WORKSPACE_DIR=$(wt-dir "$WORKSPACE_NAME")
  echo "WORKSPACE_NAME: $WORKSPACE_NAME" >&2
  echo "WORKSPACE_DIR: $WORKSPACE_DIR" >&2
  local WORKSPACE_ID=$(herdr workspace list |
    jq -r --arg workspace_name "$WORKSPACE_NAME" --arg workspace_dir "$WORKSPACE_DIR" '
      .result.workspaces[]
      | select((.label == $workspace_name or .workspace_id == $workspace_name) and (.worktree.checkout_path | test($workspace_dir)))
      | .workspace_id
    ')

  if [[ -z "$WORKSPACE_ID" ]]; then
    echo "Workspace not found: $1" >&2
    return 1
  fi

  echo "$WORKSPACE_ID"
  return 0
}

function ws-open() {
  local WORKSPACE_DIR="${1:-$PWD}"
  HELP_MSG="Usage: wt-open [-i|--interactive keyword] WORKSPACE_DIR"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print -r "${HELP_MSG}"
        return 0
        ;;
      -i|--interactive)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -i|--interactive requires a value"
          return 1
        fi
        echo "\$2 = $2"
        WORKSPACE_DIR=$(zoxide query $2 | fzf)
        shift 2
        ;;
      *)
        print -r "Error: unknown option '$1'"
        print -r "${HELP_MSG}"
        return 1
        ;;
    esac
  done
  herdr workspace create --cwd "${WORKSPACE_DIR}" --focus
}

function ws-close() {
  herdr workspace close $(ws-id $1)
}

# Worktree management functions

function wt-dir() {
  local BRANCH=$1
  git worktree list --porcelain |
    awk -v branch="refs/heads/$BRANCH" '
      /^worktree / { dir= substr($0, 10) }
      /^branch / && $2 == branch { print dir }
    '
}

function wt-switch() {
  local BASE_WORKTREE_DIR COMMAND IS_CREATE WORKSPACE_DIR
  local PROJECT TARGET_BRANCH BASE_BRANCH HERDR_WORKSPACE_LABEL BASE_BRANCH_DIR SCRIPT_DIR IS_FOCUS
  local -a ARGS

  BASE_WORKTREE_DIR="${HOME}/projects/worktrees"
  CURRENT_DIR=$(basename ${PWD})
  IS_FOCUS=true
  ARGS=()
  HELP_MSG="Usage: wt-switch -p|--project PROJECT -t|--target TARGET_BRANCH [-c|--create] [-b|--base BASE_BRANCH|origin/develop] [-l|--label HERDR_WORKSPACE_LABEL|TARGET_BRANCH|] [-f|--focus]"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print -r "${HELP_MSG}"
        return 0
        ;;
      -p|--project)
        if [[ -z ${2:-"${CURRENT_DIR}"} ]]; then
          print -r "Error: -p|--project requires a value"
          return 1
        fi
        PROJECT=$2
        shift 2
        ;;
      -t|--target)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -t|--target requires a value"
          return 1
        fi
        TARGET_BRANCH=$2
        shift 2
        ;;
      -c|--create)
        IS_CREATE=true
        shift
        ;;
      -b|--base)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -b|--base requires a value"
          return 1
        fi
        BASE_BRANCH=$2
        shift 2
        ;;
      -l|--label)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -l|--label requires a value"
          return 1
        fi
        HERDR_WORKSPACE_LABEL=$2
        shift 2
        ;;
      -f|--focus)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -f|--focus requires a value"
          return 1
        fi
        IS_FOCUS=$2
        shift 2
        ;;
      *)
        print -r "Error: unknown option '$1'"
        print -r "${HELP_MSG}"
        return 1
        ;;
    esac
  done

  if [[ -z $PROJECT ]]; then
    PROJECT="${CURRENT_DIR}"
  fi

  if [[ -z $BASE_BRANCH ]]; then
    BASE_BRANCH=origin/develop
  fi

  if [[ -z $HERDR_WORKSPACE_LABEL ]]; then
    HERDR_WORKSPACE_LABEL=$TARGET_BRANCH
  fi

  if [[ -z $IS_CREATE ]]; then
    IS_CREATE=false
  fi

  WORKSPACE_DIR="${BASE_WORKTREE_DIR}/${PROJECT}/${TARGET_BRANCH}"
  if [[ $IS_CREATE == true ]]; then
    COMMAND="create"
    ARGS+=( --base $BASE_BRANCH --branch ${TARGET_BRANCH} --path ${WORKSPACE_DIR} )
  else
    COMMAND="open"
    HERDR_WORKSPACE_ID=$(ws-id ${TARGET_BRANCH})
    ARGS+=( --cwd ${PWD} --branch ${TARGET_BRANCH} )
  fi

  if [[ $IS_FOCUS == true ]]; then
    ARGS+=( --focus )
  else
    ARGS+=( --no-focus )
  fi

  FINAL_CMD="herdr worktree ${COMMAND} --label \"${HERDR_WORKSPACE_LABEL}\" ${ARGS[@]}"

  echo "COMMAND: $COMMAND"  >&2
  echo "PROJECT: $PROJECT"  >&2
  echo "TARGET_BRANCH: $TARGET_BRANCH"  >&2
  echo "BASE_BRANCH: $BASE_BRANCH"  >&2
  echo "WORKSPACE_DIR: $WORKSPACE_DIR"  >&2
  echo "HERDR_WORKSPACE_LABEL: $HERDR_WORKSPACE_LABEL"  >&2
  echo "IS_CREATE: $IS_CREATE"  >&2
  echo "IS_FOCUS: $IS_FOCUS"  >&2
  echo  >&2
  print -r "[DEBUG] Running ${FINAL_CMD}"

  eval "${FINAL_CMD}"
}

function wt-del() {
  local CURRENT_DIR=$(basename ${PWD})
  local REPO=${2:-"${CURRENT_DIR}"}
  local WORKSPACE_NAME=$1
  local WORKSPACE_DIR=$(wt-dir "$WORKSPACE_NAME")

  wt remove --force -D $WORKSPACE_NAME
  rm -rf $WORKSPACE_DIR
  ws-close $WORKSPACE_NAME
  echo "Repo ${REPO} - Worktree $WORKSPACE_NAME deleted."
}

function start-issue() {
  local ISSUE_KEY BASE_BRANCH MODEL WORKSPACE_ID PANE_ID PIA_CMD
  local HELP_MSG="Usage: start-issue -i|--issue ISSUE_KEY -b|--base BASE_BRANCH [-m|--model MODEL]"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print -r "${HELP_MSG}"
        return 0
        ;;
      -i|--issue)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -i|--issue requires a value"
          return 1
        fi
        ISSUE_KEY=$2
        shift 2
        ;;
      -b|--base)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -b|--base requires a value"
          return 1
        fi
        BASE_BRANCH=$2
        shift 2
        ;;
      -m|--model)
        if [[ -z ${2:-} ]]; then
          print -r "Error: -m|--model requires a value"
          return 1
        fi
        MODEL=$2
        shift 2
        ;;
      *)
        print -r "Error: unknown option '$1'"
        print -r "${HELP_MSG}"
        return 1
        ;;
    esac
  done

  if [[ -z $ISSUE_KEY || -z $BASE_BRANCH ]]; then
    print -r "Error: -i and -b are required"
    print -r "${HELP_MSG}"
    return 1
  fi

  wt-switch -c -t "${ISSUE_KEY}" -b "${BASE_BRANCH}" || return 1

  # wt-switch labels the new workspace with the issue key (focused one wins if duplicated)
  WORKSPACE_ID=$(herdr workspace list | jq -r --arg label "$ISSUE_KEY" '
    [.result.workspaces[] | select(.label == $label)] | last | .workspace_id // empty')
  if [[ -z $WORKSPACE_ID ]]; then
    print -r "Error: herdr workspace not found for ${ISSUE_KEY}" >&2
    return 1
  fi

  PANE_ID=$(herdr pane list --workspace "${WORKSPACE_ID}" | jq -r '.result.panes[0].pane_id // empty')
  if [[ -z $PANE_ID ]]; then
    print -r "Error: no pane found in workspace ${WORKSPACE_ID}" >&2
    return 1
  fi

  PIA_CMD="pi -a '/approval-mode auto' '/pi-permission-suite debug on' '/kp-issue-start ${ISSUE_KEY}'"

  if [[ -n $MODEL ]]; then
    PIA_CMD="${PIA_CMD} --model ${MODEL}"
  fi

  herdr pane run "${PANE_ID}" "${PIA_CMD}"
}
# END OF FUNCTION DEFINITIONS

case "$1" in
  ws-new)
    shift
    ws-new "$@"
    ;;
  ws-list)
    shift
    ws-list "$@"
    ;;
  ws-id)
    shift
    ws-id "$@"
    ;;
  ws-open)
    shift
    ws-open "$@"
    ;;
  ws-close)
    shift
    ws-close "$@"
    ;;
  wt-dir)
    shift
    wt-dir "$@"
    ;;
  wt-switch)
    shift
    wt-switch "$@"
    ;;
  wt-del)
    shift
    wt-del "$@"
    ;;
  start-issue)
    shift
    start-issue "$@"
    ;;
  *)
    echo "Usage: bash <skill-directory>/scripts/script.sh {ws-new|ws-list|ws-id|ws-open|ws-close|wt-dir|wt-switch|wt-del|start-issue}" >&2
    exit 1
    ;;
esac
