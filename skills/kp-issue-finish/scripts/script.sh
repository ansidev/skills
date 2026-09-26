#!/bin/bash

function git-log-branch() {
  git log --graph --color=always --decorate --pretty=format:'Commit: %C(yellow)%H%C(reset) %nAuthor: %an <%ae>%nDate: %ad%nSigned by: %C(green)%GS%C(reset)%n%G?%n%n%C(green)%s%C(reset)%n%n%C(cyan)%b%C(reset)%n' "$1" -- | sed -E 's/G$/Signature status: \x1b[32mvalid signature\x1b[0m/; s/B$/Signature status: \x1b[31mbad signature\x1b[0m/; s/U$/Signature status: \x1b[31muntrusted signature\x1b[0m/; s/X$/Signature status: \x1b[31mexpired signature\x1b[0m/; s/Y$/Signature status: \x1b[31mexpired key signature\x1b[0m/; s/R$/Signature status: \x1b[31mrevoked key signature\x1b[0m/; s/E$/Signature status: \x1b[31mcannot check signature\x1b[0m/; s/N$/Signature status: \x1b[31mno signature\x1b[0m/' | sed -E '/Signed by: \x1b\[32m\x1b\[m$/d' | less -R
}

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
  *)
    echo "Usage: bash <skill-directory>/scripts/script.sh {ws-new|ws-list|ws-id|ws-open|ws-close|wt-dir|wt-switch|wt-del}" >&2
    exit 1
    ;;
esac
