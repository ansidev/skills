#!/usr/bin/env bash
# Compatibility wrapper. Host operations are centralized in ../../lib/host-runtime.sh.
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/host-runtime.sh
source "$SCRIPT_DIR/../../lib/host-runtime.sh"

case "${1:-}" in
  detect|worktree-create|worktree-lookup|agent-start|agent-prompt|workspace-close)
    op="$1"; shift
    hr_run "$op" "$@"
    ;;
  *)
    hr_fail unknown "${1:-help}" INVALID_ARGS \
      "use ../../lib/host-runtime for host lifecycle operations; supported: detect, worktree-create, worktree-lookup, agent-start, agent-prompt, workspace-close"
    ;;
esac
