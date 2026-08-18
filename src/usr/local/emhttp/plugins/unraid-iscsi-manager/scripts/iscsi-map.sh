#!/bin/bash
set -Eeuo pipefail

ZFS_BIN="${ZFS_BIN:-/sbin/zfs}"
[[ -x "$ZFS_BIN" ]] || ZFS_BIN="$(command -v zfs || true)"
[[ -n "$ZFS_BIN" && -x "$ZFS_BIN" ]] || exit 0

volume_exists() {
  "$ZFS_BIN" list -H -t volume -o name "$1" >/dev/null 2>&1
}

backstore_type_name() {
  case "${1:-}" in
    iblock_*) echo "block" ;;
    fileio_*) echo "fileio" ;;
    pscsi_*) echo "pscsi" ;;
    rd_mcp_*|rd_dr_*) echo "ramdisk" ;;
    *) echo "${1:-}" ;;
  esac
}

zvol_for_device() {
  local device="${1:-}" real volume zdev zreal
  [[ -n "$device" ]] || return 0

  if [[ "$device" == /dev/zvol/* ]]; then
    volume="${device#/dev/zvol/}"
    if volume_exists "$volume"; then
      printf '%s\n' "$volume"
      return 0
    fi
  fi

  real="$(readlink -f -- "$device" 2>/dev/null || true)"
  [[ -n "$real" ]] || return 0
  while IFS= read -r volume; do
    [[ -n "$volume" ]] || continue
    zdev="/dev/zvol/$volume"
    zreal="$(readlink -f -- "$zdev" 2>/dev/null || true)"
    if [[ -n "$zreal" && "$zreal" == "$real" ]]; then
      printf '%s\n' "$volume"
      return 0
    fi
  done < <("$ZFS_BIN" list -H -t volume -o name 2>/dev/null || true)
}

backstore_device() {
  local target_dir="${1:-}" type="${2:-}" name="${3:-}" device="" info=""
  if [[ -r "$target_dir/udev_path" ]]; then
    device="$(tr -d '\r\n' < "$target_dir/udev_path" 2>/dev/null || true)"
  fi
  if [[ -z "$device" && -r "$target_dir/info" ]]; then
    device="$(grep -Eo '/dev/[^ ,)]+' "$target_dir/info" 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "$device" && -n "$type" && -n "$name" ]] && command -v targetcli >/dev/null 2>&1; then
    info="$(targetcli "/backstores/$type/$name" info 2>/dev/null || true)"
    device="$(grep -Eo '/dev/[^ ,)]+' <<< "$info" | head -n1 || true)"
  fi
  printf '%s\n' "$device"
}

root="${TARGET_ISCSI_ROOT:-/sys/kernel/config/target/iscsi}"
[[ -d "$root" ]] || exit 0

shopt -s nullglob
for iqn_dir in "$root"/*; do
  [[ -d "$iqn_dir" ]] || continue
  iqn="$(basename "$iqn_dir")"
  for tpg_dir in "$iqn_dir"/tpgt_*; do
    [[ -d "$tpg_dir" ]] || continue
    tpg="tpg${tpg_dir##*_}"
    lun_root="$tpg_dir/lun"
    found_lun=0

    if [[ -d "$lun_root" ]]; then
      for lun_dir in "$lun_root"/lun_*; do
        [[ -d "$lun_dir" ]] || continue
        found_lun=1
        lun_id="${lun_dir##*_}"
        link="$(find "$lun_dir" -mindepth 1 -maxdepth 1 -type l -print -quit 2>/dev/null || true)"
        target_dir="$(readlink -f -- "$link" 2>/dev/null || true)"
        type=""
        backstore=""
        device=""
        zvol=""
        alua="default_tg_pt_gp"

        if [[ -n "$target_dir" && -d "$target_dir" ]]; then
          backstore="$(basename "$target_dir")"
          core_type="$(basename "$(dirname "$target_dir")")"
          type="$(backstore_type_name "$core_type")"
          device="$(backstore_device "$target_dir" "$type" "$backstore")"
          zvol="$(zvol_for_device "$device")"
        fi

        if [[ -e "$lun_dir/alua_tg_pt_gp" ]]; then
          alua="$(cat "$lun_dir/alua_tg_pt_gp" 2>/dev/null || readlink "$lun_dir/alua_tg_pt_gp" 2>/dev/null || true)"
          alua="${alua##*/}"
          [[ -n "$alua" ]] || alua="default_tg_pt_gp"
        fi

        [[ -n "$type" && -n "$backstore" ]] && backstore="/backstores/$type/$backstore"
        printf '%s\t%s\tLun%s\t%s\t%s\t%s\t%s\n' "$iqn" "$tpg" "$lun_id" "$backstore" "$device" "$alua" "$zvol"
      done
    fi

    if (( found_lun == 0 )); then
      printf '%s\t%s\t\t\t\t\t\n' "$iqn" "$tpg"
    fi
  done
done
