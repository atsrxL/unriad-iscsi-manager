#!/bin/bash
set -u

command -v targetcli >/dev/null 2>&1 || exit 0

output="$(targetcli sessions detail 2>/dev/null || true)"
[[ -n "$output" ]] || exit 0

sid=""
alias=""
session_type=""
session_state=""
initiator=""
declare -a maps=()
declare -a conns=()
sep=$'\x1f'
address_re='^address:[[:space:]]+([^[:space:]]+)[[:space:]]+\(([^)]*)\)[[:space:]]+cid:[[:space:]]+[0-9]+[[:space:]]+connection-state:[[:space:]]+([^[:space:]]+)'

reset_session() {
  sid=""
  alias=""
  session_type=""
  session_state=""
  initiator=""
  maps=()
  conns=()
}

flush_session() {
  [[ -n "$sid" ]] || return 0

  if ((${#maps[@]} == 0)); then
    maps+=("${sep}${sep}")
  fi
  if ((${#conns[@]} == 0)); then
    conns+=("${sep}${sep}")
  fi

  local map conn mapped_lun backstore mode address transport conn_state
  for map in "${maps[@]}"; do
    IFS="$sep" read -r mapped_lun backstore mode <<< "$map"
    [[ -z "$backstore" || "$backstore" == /backstores/* ]] || backstore="/backstores/$backstore"
    for conn in "${conns[@]}"; do
      IFS="$sep" read -r address transport conn_state <<< "$conn"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sid" "$alias" "$initiator" "$session_state" "$conn_state" \
        "$address" "$transport" "$mapped_lun" "$backstore" "$mode"
    done
  done
}

while IFS= read -r line; do
  trimmed="${line#"${line%%[![:space:]]*}"}"

  if [[ "$trimmed" =~ ^alias:[[:space:]](.*)[[:space:]]sid:[[:space:]]([0-9]+)[[:space:]]type:[[:space:]](.*)[[:space:]]session-state:[[:space:]]([^[:space:]]+) ]]; then
    flush_session
    reset_session
    alias="${BASH_REMATCH[1]}"
    sid="${BASH_REMATCH[2]}"
    session_type="${BASH_REMATCH[3]}"
    session_state="${BASH_REMATCH[4]}"
    continue
  fi

  if [[ "$trimmed" =~ ^name:[[:space:]]([^[:space:]]+) ]]; then
    initiator="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "$trimmed" =~ ^mapped-lun:[[:space:]]([0-9]+)[[:space:]]backstore:[[:space:]]([^[:space:]]+)[[:space:]]mode:[[:space:]]([^[:space:]]+) ]]; then
    maps+=("${BASH_REMATCH[1]}${sep}${BASH_REMATCH[2]}${sep}${BASH_REMATCH[3]}")
    continue
  fi

  if [[ "$trimmed" =~ $address_re ]]; then
    conns+=("${BASH_REMATCH[1]}${sep}${BASH_REMATCH[2]}${sep}${BASH_REMATCH[3]}")
    continue
  fi
done <<< "$output"

flush_session
