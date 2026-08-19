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

zvol_from_backstore_name() {
  local name="${1:-}" candidate
  [[ -n "$name" ]] || return 0

  # Some Unraid/QNAP target configurations name a block backstore after the
  # ZVOL and replace dataset separators with ':', e.g. intel750mlc:ai.
  candidate="${name//:/\/}"
  if [[ "$candidate" == */* ]] && volume_exists "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi
}

zvol_for_device() {
  local device="${1:-}" backstore_name="${2:-}" real volume zdev zreal inferred
  [[ -n "$device" || -n "$backstore_name" ]] || return 0

  if [[ "$device" == /dev/zvol/* ]]; then
    volume="${device#/dev/zvol/}"
    if volume_exists "$volume"; then
      printf '%s\n' "$volume"
      return 0
    fi
  fi

  if [[ -n "$device" ]]; then
    real="$(readlink -f -- "$device" 2>/dev/null || true)"
    if [[ -n "$real" ]]; then
      while IFS= read -r volume; do
        [[ -n "$volume" ]] || continue
        zdev="/dev/zvol/$volume"
        zreal="$(readlink -f -- "$zdev" 2>/dev/null || true)"
        if [[ -n "$zreal" && "$zreal" == "$real" ]]; then
          printf '%s\n' "$volume"
          return 0
        fi
      done < <("$ZFS_BIN" list -H -t volume -o name 2>/dev/null || true)
    fi
  fi

  inferred="$(zvol_from_backstore_name "$backstore_name")"
  [[ -n "$inferred" ]] && printf '%s\n' "$inferred"
}

extract_device_from_text() {
  local text="${1:-}" device=""
  [[ -n "$text" ]] || return 0

  # Prefer a stable /dev/zvol path if targetcli prints one. Otherwise accept
  # any /dev/* path and resolve it against every ZVOL symlink later.
  device="$(grep -Eo '/dev/zvol/[^ ,)\]]+' <<< "$text" | head -n1 || true)"
  if [[ -z "$device" ]]; then
    device="$(grep -Eo '/dev/[^ ,)\]]+' <<< "$text" | head -n1 || true)"
  fi
  printf '%s\n' "$device"
}

backstore_device() {
  local target_dir="${1:-}" type="${2:-}" name="${3:-}" device="" info=""

  if [[ -r "$target_dir/udev_path" ]]; then
    device="$(tr -d '\r\n' < "$target_dir/udev_path" 2>/dev/null || true)"
  fi
  if [[ -z "$device" && -r "$target_dir/info" ]]; then
    info="$(cat "$target_dir/info" 2>/dev/null || true)"
    device="$(extract_device_from_text "$info")"
  fi

  if [[ -z "$device" && -n "$type" && -n "$name" ]] && command -v targetcli >/dev/null 2>&1; then
    # targetcli-fb versions differ in how much the `info` command exposes.
    # Try both info and ls and parse the first block-device path shown.
    info="$(targetcli "/backstores/$type/$name" info 2>/dev/null || true)"
    device="$(extract_device_from_text "$info")"
    if [[ -z "$device" ]]; then
      info="$(targetcli "/backstores/$type/$name" ls 2>/dev/null || true)"
      device="$(extract_device_from_text "$info")"
    fi
  fi

  printf '%s\n' "$device"
}

backstore_unmap() {
  local target_dir="${1:-}" type="${2:-}" name="${3:-}" value="" output=""
  if [[ -r "$target_dir/attrib/emulate_tpu" ]]; then
    value="$(tr -d '\r\n' < "$target_dir/attrib/emulate_tpu" 2>/dev/null || true)"
    case "$value" in
      1) echo "on" ; return 0 ;;
      0) echo "off" ; return 0 ;;
    esac
  fi

  if command -v targetcli >/dev/null 2>&1 && [[ -n "$type" && -n "$name" ]]; then
    output="$(targetcli "/backstores/$type/$name" get attribute emulate_tpu 2>/dev/null || true)"
    if grep -Eq 'emulate_tpu([ =:]+)1([[:space:]]|$)' <<< "$output"; then
      echo "on"
      return 0
    fi
    if grep -Eq 'emulate_tpu([ =:]+)0([[:space:]]|$)' <<< "$output"; then
      echo "off"
      return 0
    fi
  fi

  echo "unknown"
}

targetcli_lun_backstore() {
  local iqn="${1:-}" tpg="${2:-}" lun_id="${3:-}" output line pair=""
  command -v targetcli >/dev/null 2>&1 || return 0
  [[ -n "$iqn" && -n "$tpg" && -n "$lun_id" ]] || return 0

  output="$(targetcli "/iscsi/$iqn/$tpg/luns/lun$lun_id" ls 2>/dev/null || true)"
  while IFS= read -r line; do
    # Typical summary contains: [block/iscsi (...)]
    pair="$(sed -nE 's/.*\[([A-Za-z0-9_-]+)\/([^][[:space:]()]+).*/\1\t\2/p' <<< "$line" | head -n1)"
    [[ -n "$pair" ]] && { printf '%b\n' "$pair"; return 0; }
  done <<< "$output"
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
        unmap="unknown"
        alua="default_tg_pt_gp"

        if [[ -n "$target_dir" && -d "$target_dir" ]]; then
          backstore="$(basename "$target_dir")"
          core_type="$(basename "$(dirname "$target_dir")")"
          type="$(backstore_type_name "$core_type")"
        else
          pair="$(targetcli_lun_backstore "$iqn" "$tpg" "$lun_id")"
          if [[ -n "$pair" ]]; then
            IFS=$'\t' read -r type backstore <<< "$pair"
            # Resolve the configfs storage object if possible for attributes.
            for candidate in /sys/kernel/config/target/core/*/"$backstore"; do
              [[ -d "$candidate" ]] || continue
              target_dir="$candidate"
              break
            done
          fi
        fi

        if [[ -n "$type" && -n "$backstore" ]]; then
          device="$(backstore_device "$target_dir" "$type" "$backstore")"
          zvol="$(zvol_for_device "$device" "$backstore")"
          unmap="$(backstore_unmap "$target_dir" "$type" "$backstore")"
        fi

        if [[ -e "$lun_dir/alua_tg_pt_gp" ]]; then
          alua="$(cat "$lun_dir/alua_tg_pt_gp" 2>/dev/null || readlink "$lun_dir/alua_tg_pt_gp" 2>/dev/null || true)"
          alua="${alua##*/}"
          [[ -n "$alua" ]] || alua="default_tg_pt_gp"
        fi

        [[ -n "$type" && -n "$backstore" ]] && backstore="/backstores/$type/$backstore"
        printf '%s\t%s\tLun%s\t%s\t%s\t%s\t%s\t%s\n' "$iqn" "$tpg" "$lun_id" "$backstore" "$device" "$alua" "$zvol" "$unmap"
      done
    fi

    if (( found_lun == 0 )); then
      printf '%s\t%s\t\t\t\t\t\t\n' "$iqn" "$tpg"
    fi
  done
done
