#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISCSI_MAP_SCRIPT="$SCRIPT_DIR/iscsi-map.sh"
ISCSI_SESSIONS_SCRIPT="$SCRIPT_DIR/iscsi-sessions.sh"

ZFS_BIN="${ZFS_BIN:-/sbin/zfs}"
ZPOOL_BIN="${ZPOOL_BIN:-/sbin/zpool}"
[[ -x "$ZFS_BIN" ]] || ZFS_BIN="$(command -v zfs || true)"
[[ -x "$ZPOOL_BIN" ]] || ZPOOL_BIN="$(command -v zpool || true)"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_zfs() {
  [[ -n "$ZFS_BIN" && -x "$ZFS_BIN" ]] || fail "zfs command not found"
  [[ -n "$ZPOOL_BIN" && -x "$ZPOOL_BIN" ]] || fail "zpool command not found"
}

valid_component() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]*$ ]]
}

valid_relative_dataset() {
  local value="${1:-}" part
  [[ -n "$value" && "$value" != /* && "$value" != */ && "$value" != *"//"* ]] || return 1
  IFS='/' read -r -a parts <<< "$value"
  for part in "${parts[@]}"; do
    valid_component "$part" || return 1
  done
}

valid_snapshot_name() {
  valid_component "${1:-}"
}

valid_size() {
  [[ "${1:-}" =~ ^[1-9][0-9]*([KkMmGgTtPp])?$ ]]
}

pool_exists() {
  "$ZPOOL_BIN" list -H -o name "$1" >/dev/null 2>&1
}

volume_exists() {
  "$ZFS_BIN" list -H -t volume -o name "$1" >/dev/null 2>&1
}

snapshot_exists() {
  "$ZFS_BIN" list -H -t snapshot -o name "$1" >/dev/null 2>&1
}

volume_pool() {
  printf '%s\n' "${1%%/*}"
}

volume_parent() {
  local value="$1"
  printf '%s\n' "${value%/*}"
}

volume_leaf() {
  printf '%s\n' "${1##*/}"
}

volume_is_iscsi_mapped() {
  local volume="$1" mapped_zvol
  [[ -f "$ISCSI_MAP_SCRIPT" ]] || return 1
  while IFS=$'\t' read -r _iqn _tpg _lun _backstore _device _alua mapped_zvol _unmap; do
    [[ "$mapped_zvol" == "$volume" ]] && return 0
  done < <(bash "$ISCSI_MAP_SCRIPT" 2>/dev/null || true)
  return 1
}

volume_has_active_iscsi_session() {
  local volume="$1" sessions backstore
  [[ -f "$ISCSI_MAP_SCRIPT" && -f "$ISCSI_SESSIONS_SCRIPT" ]] || return 1

  sessions="$(bash "$ISCSI_SESSIONS_SCRIPT" 2>/dev/null || true)"
  [[ -n "$sessions" ]] || return 1

  while IFS=$'\t' read -r _iqn _tpg _lun backstore _device _alua mapped_zvol _unmap; do
    [[ "$mapped_zvol" == "$volume" && -n "$backstore" ]] || continue
    if awk -F '\t' -v bs="$backstore" '$9 == bs { found=1 } END { exit(found ? 0 : 1) }' <<< "$sessions"; then
      return 0
    fi
  done < <(bash "$ISCSI_MAP_SCRIPT" 2>/dev/null || true)

  return 1
}

is_busy_or_exported() {
  local volume="$1" dev="/dev/zvol/$1"

  # Refresh renames the old ZVOL and creates a new block device at the old
  # dataset name. A configured LIO backstore remains attached to the old block
  # device, so even an offline mapping must be removed before refresh.
  if volume_has_active_iscsi_session "$volume" || volume_is_iscsi_mapped "$volume"; then
    return 0
  fi

  if command -v fuser >/dev/null 2>&1 && [[ -e "$dev" ]]; then
    if fuser "$dev" >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

next_snapshot_name() {
  local volume="$1" prefix="$2" base candidate index=0
  base="${prefix}-$(date +%Y%m%d-%H%M%S)"
  candidate="$base"
  while snapshot_exists "${volume}@${candidate}"; do
    index=$((index + 1))
    candidate="${base}-${index}"
  done
  printf '%s\n' "$candidate"
}

next_clone_dataset() {
  local snapshot="$1" source parent leaf index candidate
  source="${snapshot%@*}"
  parent="$(volume_parent "$source")"
  leaf="$(volume_leaf "$source")"
  index=1
  while :; do
    candidate="${parent}/${leaf}-clone${index}"
    if ! "$ZFS_BIN" list -H -o name "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
    index=$((index + 1))
  done
}

next_backup_dataset() {
  local target="$1" base candidate index=0
  base="${target}-backup-$(date +%Y%m%d-%H%M%S)"
  candidate="$base"
  while "$ZFS_BIN" list -H -o name "$candidate" >/dev/null 2>&1; do
    index=$((index + 1))
    candidate="${base}-${index}"
  done
  printf '%s\n' "$candidate"
}

cmd_pools() {
  require_zfs
  "$ZPOOL_BIN" list -H -p -o name,size,alloc,free,health
}

cmd_pool_trim_info() {
  require_zfs
  local pool autotrim
  while IFS= read -r pool; do
    [[ -n "$pool" ]] || continue
    autotrim="$("$ZPOOL_BIN" get -H -o value autotrim "$pool" 2>/dev/null || echo unknown)"
    printf '%s\t%s\n' "$pool" "$autotrim"
  done < <("$ZPOOL_BIN" list -H -o name)
}

cmd_pool_trim() {
  require_zfs
  local pool="${1:-}" action="${2:-start}"
  valid_component "$pool" || fail "invalid pool name"
  pool_exists "$pool" || fail "pool does not exist: $pool"

  case "$action" in
    start|resume)
      "$ZPOOL_BIN" trim "$pool"
      echo "TRIM started/resumed for $pool"
      ;;
    suspend)
      "$ZPOOL_BIN" trim -s "$pool"
      echo "TRIM suspended for $pool"
      ;;
    cancel)
      "$ZPOOL_BIN" trim -c "$pool"
      echo "TRIM cancelled for $pool"
      ;;
    *) fail "trim action must be start, resume, suspend, or cancel" ;;
  esac
}

cmd_set_autotrim() {
  require_zfs
  local pool="${1:-}" value="${2:-}"
  valid_component "$pool" || fail "invalid pool name"
  pool_exists "$pool" || fail "pool does not exist: $pool"
  [[ "$value" == "on" || "$value" == "off" ]] || fail "autotrim must be on or off"
  "$ZPOOL_BIN" set "autotrim=$value" "$pool"
  echo "autotrim=$value on $pool"
}

cmd_volumes() {
  require_zfs
  "$ZFS_BIN" list -H -p -t volume -o name,volsize,used,refer,compression,volblocksize,refreservation,origin
}

cmd_volume_discard_info() {
  require_zfs
  local volume dev real block queue max gran supported
  while IFS= read -r volume; do
    [[ -n "$volume" ]] || continue
    dev="/dev/zvol/$volume"
    real="$(readlink -f -- "$dev" 2>/dev/null || true)"
    block="${real##*/}"
    queue="/sys/class/block/$block/queue"
    max=""
    gran=""
    supported="unknown"

    if [[ -n "$block" && -r "$queue/discard_max_bytes" ]]; then
      max="$(cat "$queue/discard_max_bytes" 2>/dev/null || echo 0)"
      gran="$(cat "$queue/discard_granularity" 2>/dev/null || echo 0)"
      if [[ "$max" =~ ^[0-9]+$ ]]; then
        if (( max > 0 )); then supported="yes"; else supported="no"; fi
      fi
    fi

    printf '%s\t%s\t%s\t%s\n' "$volume" "$supported" "$max" "$gran"
  done < <("$ZFS_BIN" list -H -t volume -o name)
}

cmd_snapshots() {
  require_zfs
  local volume="${1:-}"
  volume_exists "$volume" || fail "volume does not exist: $volume"
  "$ZFS_BIN" list -H -p -t snapshot -r -s creation -o name,creation,used,refer "$volume" 2>/dev/null || true
}

cmd_create_volume() {
  require_zfs
  local pool="${1:-}" name="${2:-}" size="${3:-}" provisioning="${4:-}" compression="${5:-}" block="${6:-}"
  local dataset comp

  valid_component "$pool" || fail "invalid pool name"
  pool_exists "$pool" || fail "pool does not exist: $pool"
  valid_relative_dataset "$name" || fail "invalid ZVOL name; use letters, numbers, . _ : - and optional / separators"
  valid_size "$size" || fail "invalid size; examples: 512G, 1T"
  [[ "$provisioning" == "thin" || "$provisioning" == "thick" ]] || fail "provisioning must be thin or thick"
  [[ "$compression" == "on" || "$compression" == "off" ]] || fail "compression must be on or off"
  [[ "$block" =~ ^(4K|8K|16K|32K|64K|128K)$ ]] || fail "unsupported volblocksize"

  dataset="${pool}/${name}"
  if "$ZFS_BIN" list -H -o name "$dataset" >/dev/null 2>&1; then
    fail "dataset already exists: $dataset"
  fi

  comp="off"
  [[ "$compression" == "on" ]] && comp="lz4"

  args=(create -V "$size" -b "$block" -o "compression=$comp" -o "unraid-iscsi-manager:managed=yes" -o "unraid-iscsi-manager:role=volume")
  [[ "$provisioning" == "thin" ]] && args+=(-s)
  args+=("$dataset")

  "$ZFS_BIN" "${args[@]}"
  echo "Created $dataset"
}

cmd_create_snapshot() {
  require_zfs
  local volume="${1:-}" snapname="${2:-}"
  volume_exists "$volume" || fail "volume does not exist: $volume"
  if [[ -z "$snapname" ]]; then
    snapname="$(next_snapshot_name "$volume" manual)"
  fi
  valid_snapshot_name "$snapname" || fail "invalid snapshot name"
  snapshot_exists "${volume}@${snapname}" && fail "snapshot already exists"
  "$ZFS_BIN" snapshot "${volume}@${snapname}"
  echo "Created ${volume}@${snapname}"
}

cmd_delete_snapshot() {
  require_zfs
  local snapshot="${1:-}" clones
  snapshot_exists "$snapshot" || fail "snapshot does not exist: $snapshot"
  clones="$("$ZFS_BIN" get -H -o value clones "$snapshot" 2>/dev/null || true)"
  if [[ -n "$clones" && "$clones" != "-" ]]; then
    fail "snapshot has dependent clones: $clones"
  fi
  "$ZFS_BIN" destroy "$snapshot"
  echo "Deleted $snapshot"
}

cmd_clone_snapshot() {
  require_zfs
  local snapshot="${1:-}" custom="${2:-}" source parent target
  snapshot_exists "$snapshot" || fail "snapshot does not exist: $snapshot"
  source="${snapshot%@*}"
  volume_exists "$source" || fail "snapshot source is not a ZVOL: $source"
  parent="$(volume_parent "$source")"

  if [[ -n "$custom" ]]; then
    valid_component "$custom" || fail "custom clone name must be a single valid ZFS component"
    target="${parent}/${custom}"
  else
    target="$(next_clone_dataset "$snapshot")"
  fi

  if "$ZFS_BIN" list -H -o name "$target" >/dev/null 2>&1; then
    fail "target already exists: $target"
  fi

  "$ZFS_BIN" clone -o "unraid-iscsi-manager:managed=yes" -o "unraid-iscsi-manager:role=clone" "$snapshot" "$target"
  echo "Cloned $snapshot -> $target"
}

cmd_refresh() {
  require_zfs
  local source="${1:-}"; shift || true
  local target backup snapshot_name snapshot pool target_pool
  local -a targets=("$@")

  volume_exists "$source" || fail "source volume does not exist: $source"
  ((${#targets[@]} > 0)) || fail "select at least one target volume"
  pool="$(volume_pool "$source")"

  # Full preflight before mutating anything.
  for target in "${targets[@]}"; do
    volume_exists "$target" || fail "target volume does not exist: $target"
    [[ "$target" != "$source" ]] || fail "source cannot also be a refresh target"
    target_pool="$(volume_pool "$target")"
    [[ "$target_pool" == "$pool" ]] || fail "cross-pool refresh is not supported in V1: $target"
    if is_busy_or_exported "$target"; then
      fail "target is iSCSI mapped/active or locally busy; remove its LIO mapping before refresh: $target"
    fi
  done

  if is_busy_or_exported "$source"; then
    fail "source is iSCSI mapped/active or locally busy; remove its LIO mapping before creating a refresh base: $source"
  fi

  snapshot_name="$(next_snapshot_name "$source" refresh)"
  snapshot="${source}@${snapshot_name}"
  "$ZFS_BIN" snapshot "$snapshot"
  echo "Created refresh snapshot $snapshot"

  for target in "${targets[@]}"; do
    backup="$(next_backup_dataset "$target")"
    "$ZFS_BIN" rename "$target" "$backup"
    "$ZFS_BIN" set "unraid-iscsi-manager:managed=yes" "$backup" || true
    "$ZFS_BIN" set "unraid-iscsi-manager:role=backup" "$backup" || true

    if "$ZFS_BIN" clone -o "unraid-iscsi-manager:managed=yes" -o "unraid-iscsi-manager:role=clone" "$snapshot" "$target"; then
      echo "Refreshed $target (previous volume kept as $backup)"
    else
      echo "Clone failed for $target; restoring $backup" >&2
      if ! "$ZFS_BIN" list -H -o name "$target" >/dev/null 2>&1; then
        "$ZFS_BIN" rename "$backup" "$target" || true
      fi
      fail "refresh failed for $target"
    fi
  done
}

cmd_busy() {
  require_zfs
  local volume="${1:-}"
  volume_exists "$volume" || fail "volume does not exist: $volume"
  if volume_has_active_iscsi_session "$volume"; then
    echo "active-session"
  elif volume_is_iscsi_mapped "$volume"; then
    echo "mapped"
  elif command -v fuser >/dev/null 2>&1 && [[ -e "/dev/zvol/$volume" ]] && fuser "/dev/zvol/$volume" >/dev/null 2>&1; then
    echo "local-busy"
  else
    echo "clear"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  zvol-manager.sh pools
  zvol-manager.sh pool-trim-info
  zvol-manager.sh pool-trim <pool> <start|resume|suspend|cancel>
  zvol-manager.sh set-autotrim <pool> <on|off>
  zvol-manager.sh volumes
  zvol-manager.sh volume-discard-info
  zvol-manager.sh snapshots <zvol>
  zvol-manager.sh create-volume <pool> <name> <size> <thin|thick> <on|off> <4K|8K|16K|32K|64K|128K>
  zvol-manager.sh create-snapshot <zvol> [name]
  zvol-manager.sh delete-snapshot <zvol@snapshot>
  zvol-manager.sh clone-snapshot <zvol@snapshot> [custom-leaf-name]
  zvol-manager.sh refresh <source-zvol> <target-zvol> [target-zvol ...]
  zvol-manager.sh busy <zvol>
USAGE
}

case "${1:-}" in
  pools) shift; cmd_pools "$@" ;;
  pool-trim-info) shift; cmd_pool_trim_info "$@" ;;
  pool-trim) shift; cmd_pool_trim "$@" ;;
  set-autotrim) shift; cmd_set_autotrim "$@" ;;
  volumes) shift; cmd_volumes "$@" ;;
  volume-discard-info) shift; cmd_volume_discard_info "$@" ;;
  snapshots) shift; cmd_snapshots "$@" ;;
  create-volume) shift; cmd_create_volume "$@" ;;
  create-snapshot) shift; cmd_create_snapshot "$@" ;;
  delete-snapshot) shift; cmd_delete_snapshot "$@" ;;
  clone-snapshot) shift; cmd_clone_snapshot "$@" ;;
  refresh) shift; cmd_refresh "$@" ;;
  busy) shift; cmd_busy "$@" ;;
  -h|--help|help|'') usage ;;
  *) fail "unknown command: $1" ;;
esac
