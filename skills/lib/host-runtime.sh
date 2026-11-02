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

hr_workspace_close_desktop() {
  local issue="$1" out address closed=0
  out=$(hc ls --label "herdr.issue=$issue" 2>&1)
  address=$(printf '%s\n' "$out" | hr_address)
  if [[ -n "$address" ]] && hc kill "$address" >/dev/null 2>&1; then closed=1; fi
  hr_ok herdr-desktop workspace-close "{\"closed\":$closed,\"label\":\"herdr.issue=$issue\"}"
}

hr_run() {
  local op="$1"; shift
  local issue="" text="" args="" workspace=""
  while (($#)); do
    case "$1" in
      --issue) issue="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --args) args="$2"; shift 2 ;;
      --workspace) workspace="$2"; shift 2 ;;
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
    workspace-close)
      [[ -n "$issue" ]] || { hr_fail "$runtime" "$op" INVALID_ARGS "--issue is required"; return; }
      case "$runtime" in herdr-desktop) hr_workspace_close_desktop "$issue" ;; outside) hr_ok outside workspace-close '{"closed":0,"note":"outside host: nothing to close"}' ;; herdr-tui) hr_fail herdr-tui workspace-close RUNTIME_UNSUPPORTED "Herdr TUI adapter is not yet available" ;; esac ;;
    *) hr_fail "$runtime" "$op" INVALID_ARGS "unknown operation '$op'" ;;
  esac
}
