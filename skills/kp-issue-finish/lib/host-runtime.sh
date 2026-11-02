#!/usr/bin/env bash
# Shared runtime detection and lifecycle adapters for kp-issue skills.

hr_json_string() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n'; }

hr_ok() { printf '{"ok":true,"runtime":"%s","op":"%s","data":%s}\n' "$1" "$2" "$3"; }
hr_error() {
  local message
  message=$(hr_json_string "$4")
  printf '{"ok":false,"runtime":"%s","op":"%s","error":{"code":"%s","message":"%s"}}\n' "$1" "$2" "$3" "$message"
}
hr_fail() { hr_error "$1" "$2" "$3" "$4"; return 1; }

# Writes the runtime to stdout. Detection is deliberate: no UI ordering/state probes.
hr_detect_runtime() {
  HR_DETECT_ERROR=""
  HR_RUNTIME=""
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    command -v herdr >/dev/null 2>&1 && { HR_RUNTIME=herdr-tui; printf '%s\n' "$HR_RUNTIME"; return 0; }
    HR_DETECT_ERROR="HERDR_ENV=1 but the 'herdr' binary is not on PATH"
    HR_RUNTIME=unknown
    printf '%s\n' "$HR_RUNTIME"; return 1
  fi
  if command -v herdr-app >/dev/null 2>&1; then
    if command -v hc >/dev/null 2>&1 && hc server status >/dev/null 2>&1; then
      HR_RUNTIME=herdr-desktop
      printf '%s\n' "$HR_RUNTIME"; return 0
    fi
    HR_DETECT_ERROR="herdr-app found but 'hc' is missing or herdr-core is not reachable (hc server status failed)"
    HR_RUNTIME=unknown
    printf '%s\n' "$HR_RUNTIME"; return 1
  fi
  HR_RUNTIME=outside
  printf '%s\n' "$HR_RUNTIME"
}

hr_address() { sed -n 's/.*"address"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1; }

hr_repo_name() {
  local repo="${1:-}"
  if [[ -n "$repo" ]]; then
    # Accept either a bare repo name or a repo path; the name is the leaf.
    repo="${repo%/}"
    printf '%s\n' "${repo##*/}"
    return 0
  fi
  local common_dir
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  printf '%s\n' "$(basename "${common_dir%/.git}")"
}

hr_worktree_root() { printf '%s' "${HR_WORKTREE_ROOT:-${HOME}/projects/worktrees}"; }

hr_git_worktree_create() {
  local issue="$1" base="$2" repo out
  repo=$(hr_repo_name "${3:-}") || { hr_fail "$HR_RUNTIME" worktree-create WORKTREE_CREATE_FAILED "cannot resolve repo name; pass --repo"; return; }
  if command -v wt >/dev/null 2>&1; then
    hr_wt_worktree_create "$issue" "$base"
    return
  fi
  local path
  path="$(hr_worktree_root)/$repo/$issue"
  mkdir -p "$(hr_worktree_root)/$repo"
  if ! out=$(git worktree add "$path" -b "$issue" "$base" 2>&1); then
    hr_fail "$HR_RUNTIME" worktree-create WORKTREE_CREATE_FAILED "git worktree add failed: $out"; return
  fi
  hr_ok "$HR_RUNTIME" worktree-create "{\"worktree_path\":\"$path\",\"branch\":\"$issue\",\"base\":\"$base\"}"
}

# Worktrunk: path template resolves via wt's own config; look the path back up
# from its JSON output instead of assuming ~/projects/worktrees/<repo>/<issue>.
hr_wt_worktree_create() {
  local issue="$1" base="$2" out path
  if ! out=$(wt switch --create "$issue" --base "$base" --no-cd --no-hooks --format json -y 2>&1); then
    hr_fail "$HR_RUNTIME" worktree-create WORKTREE_CREATE_FAILED "wt switch failed: $out"; return
  fi
  path=$(printf '%s\n' "$out" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  if [[ -z "$path" ]]; then
    hr_fail "$HR_RUNTIME" worktree-create WORKTREE_CREATE_FAILED "wt switch returned no path: $out"; return
  fi
  hr_ok "$HR_RUNTIME" worktree-create "{\"worktree_path\":\"$path\",\"branch\":\"$issue\",\"base\":\"$base\"}"
}

hr_worktree_create_tui() {
  local issue="$1" base="$2" repo="${3:-}" focus="${4:-false}" path out workspace_id
  repo=$(hr_repo_name "$repo") || { hr_fail herdr-tui worktree-create WORKTREE_CREATE_FAILED "cannot resolve repo name; pass --repo"; return; }
  path="$(hr_worktree_root)/$repo/$issue"
  mkdir -p "$(hr_worktree_root)/$repo"
  local focus_flags=()
  [[ "$focus" == false ]] && focus_flags=(--no-focus)
  if ! out=$(herdr worktree create --branch "$issue" --label "$issue" --path "$path" "${focus_flags[@]}" 2>&1); then
    hr_fail herdr-tui worktree-create WORKTREE_CREATE_FAILED "herdr worktree create failed: $out"; return
  fi
  workspace_id=$(printf '%s\n' "$out" | sed -n 's/.*"workspace_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  local ws_json
  if [[ -n "$workspace_id" ]]; then ws_json="\"$workspace_id\""; else ws_json=null; fi
  hr_ok herdr-tui worktree-create "{\"worktree_path\":\"$path\",\"branch\":\"$issue\",\"base\":\"$base\",\"workspace_id\":$ws_json}"
}

hr_worktree_create_desktop() {
  hr_git_worktree_create "$@"
}

hr_worktree_create_outside() {
  hr_git_worktree_create "$@"
}

hr_git_worktree_lookup() {
  local issue="$1" path
  if command -v wt >/dev/null 2>&1; then
    path=$(wt list --branches --format json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for i in d.get("items", []):
    if i.get("branch") == sys.argv[1] and i.get("worktree"):
        print(i["worktree"]["path"])
' "$issue" 2>/dev/null)
  fi
  [[ -n "$path" ]] || path=$(git worktree list --porcelain 2>/dev/null | awk -v I="refs/heads/$issue" '
    /^worktree / { p=substr($0,10) }
    /^branch / { if ($2==I) { print p; exit 0 } }
  ')
  [[ -n "$path" ]] || { hr_fail "$HR_RUNTIME" worktree-lookup WORKTREE_NOT_FOUND "no worktree on branch $issue"; return; }
  hr_ok "$HR_RUNTIME" worktree-lookup "{\"worktree_path\":\"$path\",\"workspace_id\":null}"
}

hr_worktree_lookup_tui() {
  local issue="$1" wt_path workspace_id=null workspaces
  wt_path=$(hr_git_worktree_path_tui "$issue") || { hr_fail herdr-tui worktree-lookup WORKTREE_NOT_FOUND "no worktree on branch $issue"; return; }
  workspaces=$(herdr workspace list 2>&1) || workspaces=""
  if [[ -n "$workspaces" ]]; then
    while IFS= read -r line; do
      local wid wpath
      wid=$(printf '%s' "$line" | sed -n 's/.*"workspace_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      wpath=$(printf '%s' "$line" | sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      if [[ -n "$wid" && "$wpath" == "$wt_path" ]]; then workspace_id="\"$wid\""; break; fi
    done <<< "$workspaces"
  fi
  hr_ok herdr-tui worktree-lookup "{\"worktree_path\":\"$wt_path\",\"workspace_id\":$workspace_id}"
}

hr_git_worktree_path() {
  local issue="$1" path=""
  if command -v wt >/dev/null 2>&1; then
    hr_git_worktree_lookup "$issue" >/dev/null 2>&1 && path=$(hr_git_worktree_lookup "$issue" 2>/dev/null | sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi
  [[ -n "$path" ]] || path=$(git worktree list --porcelain 2>/dev/null | awk -v I="refs/heads/$issue" '
    /^worktree / { p=substr($0,10) }
    /^branch / { if ($2==I) { print p; exit 0 } }
  ')
  [[ -n "$path" ]] || return 1
  printf '%s\n' "$path"
}

hr_git_worktree_path_tui() {
  hr_git_worktree_path "$@"
}

hr_worktree_lookup_desktop() { hr_git_worktree_lookup "$@"; }
hr_worktree_lookup_outside() { hr_git_worktree_lookup "$@"; }

hr_workspace_close_tui() {
  local issue="$1" wid
  wid=$(hr_run worktree-lookup --issue "$issue" 2>/dev/null | sed -n 's/.*"workspace_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [[ -z "$wid" ]]; then
    hr_ok herdr-tui workspace-close '{"closed":0,"note":"no Herdr workspace found for this issue"}'
    return
  fi
  if ! herdr workspace close "$wid" >/dev/null 2>&1; then
    hr_fail herdr-tui workspace-close CLOSE_FAILED "herdr workspace close $wid failed"
    return
  fi
  hr_ok herdr-tui workspace-close "{\"closed\":1,\"workspace_id\":\"$wid\"}"
}

hr_agent_start_tui() {
  local issue="$1" workspace="$2" args="$3" panes pane_id name
  panes=$(herdr pane list --workspace "$workspace" 2>&1) || { hr_fail herdr-tui agent-start AGENT_START_FAILED "herdr pane list failed: $panes"; return; }
  pane_id=$(printf '%s\n' "$panes" | sed -n 's/.*"pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  [[ -n "$pane_id" ]] || { hr_fail herdr-tui agent-start AGENT_START_FAILED "no pane found in workspace $workspace"; return; }
  name="issue-$(printf '%s' "$issue" | tr '[:upper:]' '[:lower:]')"
  if ! herdr agent start "$name" --kind pi --pane "$pane_id" -- $args >/dev/null 2>&1; then
    hr_fail herdr-tui agent-start AGENT_START_FAILED "herdr agent start failed"; return
  fi
  hr_ok herdr-tui agent-start "{\"agent_name\":\"$name\",\"pane_id\":\"$pane_id\",\"workspace_id\":\"$workspace\"}"
}

hr_agent_prompt_tui() {
  local issue="$1" text="$2" name
  name="issue-$(printf '%s' "$issue" | tr '[:upper:]' '[:lower:]')"
  if ! herdr agent prompt "$name" "$text" >/dev/null 2>&1; then
    hr_fail herdr-tui agent-prompt AGENT_PROMPT_FAILED "herdr agent prompt failed"; return
  fi
  hr_ok herdr-tui agent-prompt "{\"agent_name\":\"$name\"}"
}

hr_agent_start_desktop() {
  local issue="$1" args="$2" out address
  if ! out=$(hc run --bg --keep --label "herdr.issue=$issue" -- $args 2>&1); then
    hr_fail herdr-desktop agent-start AGENT_START_FAILED "hc run failed: $out"; return
  fi
  address=$(printf '%s\n' "$out" | hr_address)
  [[ -n "$address" ]] || { hr_fail herdr-desktop agent-start AGENT_START_FAILED "hc run returned no terminal address"; return; }
  hr_ok herdr-desktop agent-start "{\"terminal\":\"$address\",\"label\":\"herdr.issue=$issue\"}"
}

hr_agent_prompt_desktop() {
  local issue="$1" text="$2" out address
  out=$(hc ls --label "herdr.issue=$issue" 2>&1)
  address=$(printf '%s\n' "$out" | hr_address)
  [[ -n "$address" ]] || { hr_fail herdr-desktop agent-prompt AGENT_PROMPT_FAILED "no terminal labeled herdr.issue=$issue found via hc ls"; return; }
  if ! hc send "$address" "$text" >/dev/null 2>&1; then
    hr_fail herdr-desktop agent-prompt AGENT_PROMPT_FAILED "hc send failed"; return
  fi
  hr_ok herdr-desktop agent-prompt "{\"terminal\":\"$address\"}"
}

hr_hc_terminals() { hc ls 2>/dev/null || true; }

# Prints the addresses of live terminals whose cwd is the issue worktree path
# (or a subdirectory of it), one per line. Terminals created inside the herdr
# desktop app carry no herdr.issue label, so cwd is the only reliable match.
hr_hc_addresses_by_cwd() {
  local issue="$1" wt_path="${HR_LAST_WORKTREE_PATH:-}"
  hr_hc_terminals | python3 -c '
import json, os, sys
issue, wt_path = sys.argv[1], sys.argv[2]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in d.get("terminals", []):
    cwd = t.get("cwd", "")
    if cwd == wt_path or (wt_path and cwd.startswith(wt_path + os.sep)):
        print(t.get("address", ""))
' "$issue" "$wt_path" 2>/dev/null
}

hr_workspace_close_desktop() {
  local issue="$1" out address closed=0 addresses
  # 1) Terminals the skills started themselves carry the herdr.issue label.
  out=$(hc ls --label "herdr.issue=$issue" 2>&1)
  address=$(printf '%s\n' "$out" | hr_address)
  if [[ -n "$address" ]] && hc kill "$address" >/dev/null 2>&1; then closed=1; fi
  # 2) Terminals opened inside the desktop app on the issue worktree: no label,
  #    match by cwd. Kill every remaining live one.
  for address in $(hr_hc_addresses_by_cwd "$issue"); do
    if hc kill "$address" >/dev/null 2>&1; then closed=$((closed + 1)); fi
  done
  hr_ok herdr-desktop workspace-close "{\"closed\":$closed,\"label\":\"herdr.issue=$issue\"}"
}

# Worktree/branch cleanup: worktrunk when available (it reaps background
# processes and deletes merged branches safely), plain git otherwise.
hr_git_worktree_remove() {
  local issue="$1" force="${2:-false}" path
  path=$(hr_git_worktree_lookup "$issue" 2>/dev/null | sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [[ -z "$path" ]]; then
    hr_ok "$HR_RUNTIME" worktree-remove "{\"removed\":0,\"note\":\"no worktree on branch $issue\"}"
    return
  fi
  if command -v wt >/dev/null 2>&1; then
    local wt_flags=()
    [[ "$force" == true ]] && wt_flags+=(--force)
    if ! out=$(wt remove "$issue" "${wt_flags[@]}" -y 2>&1); then
      hr_fail "$HR_RUNTIME" worktree-remove WORKTREE_REMOVE_FAILED "wt remove failed: $out"; return
    fi
    hr_ok "$HR_RUNTIME" worktree-remove "{\"removed\":1,\"worktree_path\":\"$path\"}"
    return
  fi
  local git_flags=()
  [[ "$force" == true ]] && git_flags+=(--force)
  if ! out=$(git worktree remove "${git_flags[@]}" "$path" 2>&1); then
    hr_fail "$HR_RUNTIME" worktree-remove WORKTREE_REMOVE_FAILED "git worktree remove failed: $out"; return
  fi
  git branch -D "$issue" >/dev/null 2>&1
  hr_ok "$HR_RUNTIME" worktree-remove "{\"removed\":1,\"worktree_path\":\"$path\"}"
}

hr_run() {
  local op="$1"; shift
  local issue="" text="" args="" workspace="" base="" repo="" focus="" force="" worktree_path=""
  while (($#)); do
    case "$1" in
      --issue) issue="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --args) args="$2"; shift 2 ;;
      --workspace) workspace="$2"; shift 2 ;;
      --base) base="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      --focus) focus="$2"; shift 2 ;;
      --worktree-path) worktree_path="$2"; shift 2 ;;
      --force) force=true; shift ;;
      *) hr_fail unknown "$op" INVALID_ARGS "unknown option $1"; return ;;
    esac
  done
  local runtime detect_status
  hr_detect_runtime >/dev/null
  detect_status=$?
  runtime="$HR_RUNTIME"
  if (( detect_status != 0 )) || [[ "$runtime" == unknown ]]; then hr_fail unknown "$op" DETECT_FAILED "$HR_DETECT_ERROR"; return; fi
  case "$op" in
    detect) hr_ok "$runtime" detect "{\"runtime\":\"$runtime\"}" ;;
    agent-start)
      [[ -n "$issue" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue is required"; return; }
      case "$runtime" in herdr-desktop) hr_agent_start_desktop "$issue" "$args" ;; herdr-tui) [[ -n "$workspace" ]] || { hr_fail herdr-tui agent-start INVALID_ARGS "--workspace is required for Herdr TUI"; return; }; hr_agent_start_tui "$issue" "$workspace" "$args" ;; outside) hr_fail outside agent-start NO_HOST_AGENT "no managed host detected; agents cannot be launched outside Herdr" ;; esac ;;
    agent-prompt)
      [[ -n "$issue" && -n "$text" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue and --text are required"; return; }
      case "$runtime" in herdr-desktop) hr_agent_prompt_desktop "$issue" "$text" ;; herdr-tui) hr_agent_prompt_tui "$issue" "$text" ;; outside) hr_fail outside agent-prompt NO_HOST_AGENT "no managed host detected; there is no agent to prompt" ;; esac ;;
    worktree-create)
      [[ -n "$issue" && -n "$base" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue and --base are required"; return; }
      case "$runtime" in herdr-tui) hr_worktree_create_tui "$issue" "$base" "$repo" "${focus:-false}" ;; herdr-desktop|outside) hr_git_worktree_create "$issue" "$base" "$repo" ;; esac ;;
    worktree-lookup)
      [[ -n "$issue" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue is required"; return; }
      case "$runtime" in herdr-tui) hr_worktree_lookup_tui "$issue" ;; herdr-desktop|outside) hr_git_worktree_lookup "$issue" ;; esac ;;
    worktree-remove)
      [[ -n "$issue" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue is required"; return; }
      case "$runtime" in
        herdr-tui) hr_fail herdr-tui worktree-remove RUNTIME_UNSUPPORTED "close the Herdr workspace instead; use wt remove / git worktree remove directly" ;;
        herdr-desktop|outside)
          HR_LAST_WORKTREE_PATH=$(hr_git_worktree_path "$issue" 2>/dev/null || true)
          export HR_LAST_WORKTREE_PATH
          hr_git_worktree_remove "$issue" "${force:-false}" ;;
      esac ;;
    workspace-close)
      [[ -n "$issue" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue is required"; return; }
      case "$runtime" in
        herdr-desktop)
          HR_LAST_WORKTREE_PATH="${worktree_path:-$(hr_git_worktree_path "$issue" 2>/dev/null || true)}"
          export HR_LAST_WORKTREE_PATH
          hr_workspace_close_desktop "$issue" ;;
        outside) hr_ok outside workspace-close '{"closed":0,"note":"outside host: nothing to close"}' ;;
        herdr-tui) hr_workspace_close_tui "$issue" ;;
      esac ;;
    *) hr_fail "$runtime" "$op" INVALID_ARGS "unknown operation '$op'" ;;
  esac
}
