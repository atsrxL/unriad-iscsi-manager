#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_SCRIPT="$SCRIPT_DIR/iscsi-map.sh"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v targetcli >/dev/null 2>&1 || fail "targetcli command not found"

valid_backstore() {
  [[ "${1:-}" =~ ^/backstores/block/[A-Za-z0-9._:-]+$ ]]
}

mapped_backstore() {
  local wanted="$1" found=""
  [[ -f "$MAP_SCRIPT" ]] || return 1
  found="$(bash "$MAP_SCRIPT" 2>/dev/null | awk -F '\t' -v bs="$wanted" '$4 == bs { print "yes"; exit }')"
  [[ "$found" == "yes" ]]
}

get_value() {
  local backstore="$1" output value
  valid_backstore "$backstore" || fail "invalid block backstore path"
  mapped_backstore "$backstore" || fail "backstore is not mapped by the current LIO configuration: $backstore"

  output="$(targetcli "$backstore" get attribute emulate_tpu 2>&1)" || fail "$output"
  value="$(sed -nE 's/.*emulate_tpu[[:space:]]*=[[:space:]]*['\"']?([01]).*/\1/p' <<< "$output" | tail -n1)"
  [[ "$value" == "0" || "$value" == "1" ]] || fail "could not read emulate_tpu for $backstore: $output"
  printf '%s\n' "$value"
}

set_value() {
  local backstore="$1" requested="$2" bit output actual
  valid_backstore "$backstore" || fail "invalid block backstore path"
  mapped_backstore "$backstore" || fail "backstore is not mapped by the current LIO configuration: $backstore"

  case "$requested" in
    on|1|true) bit=1 ;;
    off|0|false) bit=0 ;;
    *) fail "UNMAP value must be on or off" ;;
  esac

  output="$(targetcli "$backstore" set attribute "emulate_tpu=$bit" 2>&1)" || fail "$output"
  actual="$(get_value "$backstore")"
  [[ "$actual" == "$bit" ]] || fail "emulate_tpu verification failed for $backstore"

  if [[ "$bit" == "1" ]]; then
    echo "UNMAP enabled for $backstore (emulate_tpu=1). Reconnect the Windows iSCSI disk before running ReTrim."
  else
    echo "UNMAP disabled for $backstore (emulate_tpu=0)."
  fi
}

case "${1:-}" in
  get)
    [[ $# -eq 2 ]] || fail "usage: iscsi-unmap.sh get /backstores/block/name"
    get_value "$2"
    ;;
  set)
    [[ $# -eq 3 ]] || fail "usage: iscsi-unmap.sh set /backstores/block/name <on|off>"
    set_value "$2" "$3"
    ;;
  *)
    fail "usage: iscsi-unmap.sh <get|set> ..."
    ;;
esac
