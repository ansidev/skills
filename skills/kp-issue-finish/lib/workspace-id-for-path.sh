#!/usr/bin/env bash
# Extracts the Herdr workspace_id whose worktree.checkout_path equals the
# path given as $1 from a `herdr workspace list` JSON payload on stdin.
# Prints the workspace_id on stdout and exits 0 when found; exits 1 with no
# output when not found; exits 2 on usage/parse errors.

set -u

target_path="${1:-}"
if [[ -z "$target_path" ]]; then
  echo "usage: $0 <checkout_path>" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

# Herdr wraps the payload as { id, result: { workspaces: [...] } };
# unwrap both that envelope and a bare { workspaces: [...] }.
id=$(jq -r --arg p "$target_path" '
  (.result.workspaces // .workspaces // [])[]
  | select((.worktree.checkout_path // "") == $p)
  | .workspace_id
' 2>/dev/null | head -n1)

if [[ -z "$id" || "$id" == "null" ]]; then
  exit 1
fi

printf '%s\n' "$id"
exit 0
