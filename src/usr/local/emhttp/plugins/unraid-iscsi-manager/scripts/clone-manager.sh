#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZVOL_MANAGER_SCRIPT="${ZVOL_MANAGER_SCRIPT:-$SCRIPT_DIR/zvol-manager.sh}"
ZFS_BIN="${ZFS_BIN:-/sbin/zfs}"
[[ -x "$ZFS_BIN" ]] || ZFS_BIN="$(command -v zfs || true)"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_tools() {
  [[ -n "$ZFS_BIN" && -x "$ZFS_BIN" ]] || fail "zfs command not found"
  [[ -f "$ZVOL_MANAGER_SCRIPT" ]] || fail "zvol-manager.sh not found"
}

volume_exists() {
  "$ZFS_BIN" list -H -t volume -o name "$1" >/dev/null 2>&1
}

cmd_delete_clone() {
  require_tools
  local clone="${1:-}" origin busy snapshots

  [[ -n "$clone" ]] || fail "clone name is required"
  volume_exists "$clone" || fail "ZVOL does not exist: $clone"

  origin="$("$ZFS_BIN" get -H -o value origin "$clone" 2>/dev/null || true)"
  [[ -n "$origin" && "$origin" != "-" ]] || fail "refusing to delete a non-clone ZVOL: $clone"

  busy="$(bash "$ZVOL_MANAGER_SCRIPT" busy "$clone" 2>&1 || true)"
  case "$busy" in
    clear) ;;
    active-session) fail "clone has an active iSCSI session: $clone" ;;
    mapped) fail "clone is still mapped to an iSCSI LUN; remove the mapping first: $clone" ;;
    local-busy) fail "clone block device is in use locally: $clone" ;;
    *) fail "could not verify clone is safe to delete: ${busy:-unknown status}" ;;
  esac

  snapshots="$("$ZFS_BIN" list -H -t snapshot -r -o name "$clone" 2>/dev/null || true)"
  if [[ -n "$snapshots" ]]; then
    fail "clone has snapshots; delete its snapshots first: $(tr '\n' ' ' <<< "$snapshots" | sed 's/[[:space:]]*$//')"
  fi

  # Intentionally non-recursive. If the clone has unexpected descendants or
  # other dependencies, ZFS will refuse the destroy rather than cascading it.
  "$ZFS_BIN" destroy "$clone"
  echo "Deleted clone $clone (origin: $origin)"
}

usage() {
  cat <<'USAGE'
Usage:
  clone-manager.sh delete <clone-zvol>
USAGE
}

case "${1:-}" in
  delete) shift; cmd_delete_clone "$@" ;;
  -h|--help|help|'') usage ;;
  *) fail "unknown command: $1" ;;
esac
