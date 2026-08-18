#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_SCRIPT="${IZM_MAP_SCRIPT:-$SCRIPT_DIR/iscsi-map.sh}"
UNMAP_SCRIPT="${IZM_UNMAP_SCRIPT:-$SCRIPT_DIR/iscsi-unmap.sh}"
CONFIG_DIR="${IZM_CONFIG_DIR:-/boot/config/plugins/unraid-iscsi-manager}"
CONFIG_FILE="${IZM_CONFIG_FILE:-$CONFIG_DIR/settings.cfg}"
LOCK_FILE="${IZM_UNMAP_LOCK:-/var/run/unraid-iscsi-manager-unmap.lock}"

log() {
  logger -t unraid-iscsi-manager -- "$*" 2>/dev/null || true
}

policy_enabled() {
  [[ -r "$CONFIG_FILE" ]] || return 1
  grep -Eq '^AUTO_UNMAP=(1|yes|on|true)$' "$CONFIG_FILE" 2>/dev/null
}

[[ -f "$MAP_SCRIPT" && -f "$UNMAP_SCRIPT" ]] || exit 0
policy_enabled || exit 0

# Avoid overlapping cron, page-load, and install reconciliation runs.
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# Do not parse TSV with `IFS=$'\t' read a b ...`: tab is IFS whitespace, so
# adjacent tabs can collapse and shift an empty ZVOL field into the next
# column. Extract the exact fields with cut so non-ZVOL block devices can
# never be mistaken for ZVOLs.
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  backstore="$(printf '%s\n' "$line" | cut -f4)"
  zvol="$(printf '%s\n' "$line" | cut -f7)"
  unmap="$(printf '%s\n' "$line" | cut -f8)"

  [[ -n "$zvol" ]] || continue
  [[ "$backstore" == /backstores/block/* ]] || continue
  [[ "$unmap" == "on" ]] && continue

  if output="$(bash "$UNMAP_SCRIPT" set "$backstore" on 2>&1)"; then
    log "Auto-enabled SCSI UNMAP for $backstore ($zvol)"
  else
    log "Failed to auto-enable SCSI UNMAP for $backstore ($zvol): $output"
  fi
done < <(bash "$MAP_SCRIPT" 2>/dev/null || true)
