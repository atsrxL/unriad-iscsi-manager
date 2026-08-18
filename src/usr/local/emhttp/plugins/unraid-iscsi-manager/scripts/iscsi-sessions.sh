#!/bin/bash
set -u

root="${TARGET_ISCSI_ROOT:-/sys/kernel/config/target/iscsi}"

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
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sid" "$alias" "$initiator" "$session_state" "$conn_state" \
        "$address" "$transport" "$mapped_lun" "$backstore" "$mode" "" ""
    done
  done
}

parse_targetcli_sessions() {
  command -v targetcli >/dev/null 2>&1 || return 0
  local output line trimmed
  output="$(targetcli sessions detail 2>/dev/null || true)"
  [[ -n "$output" ]] || return 0

  reset_session
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
}

peer_ips_for_tpg() {
  local tpg_dir="$1" np_dir portal port endpoint ip
  local -a ports=() peers=()
  command -v ss >/dev/null 2>&1 || return 0

  shopt -s nullglob
  for np_dir in "$tpg_dir"/np/*; do
    [[ -d "$np_dir" ]] || continue
    portal="$(basename "$np_dir")"
    port="${portal##*:}"
    [[ "$port" =~ ^[0-9]+$ ]] && ports+=("$port")
  done
  shopt -u nullglob
  ((${#ports[@]} > 0)) || ports=(3260)

  while IFS= read -r endpoint; do
    [[ -n "$endpoint" ]] || continue
    ip="${endpoint%:*}"
    ip="${ip#\[}"
    ip="${ip%\]}"
    peers+=("$ip")
  done < <(
    for port in "${ports[@]}"; do
      ss -Htn state established "( sport = :$port )" 2>/dev/null | awk '{print $NF}'
    done | sort -u
  )

  printf '%s\n' "${peers[@]}"
}

parse_dynamic_sessions() {
  [[ -d "$root" ]] || return 0
  local iqn_dir tpg_dir dyn_file target_iqn target_tpg dyn_initiator address=""
  local -a dyn_initiators=() peers=()

  shopt -s nullglob
  for iqn_dir in "$root"/*; do
    [[ -d "$iqn_dir" ]] || continue
    target_iqn="$(basename "$iqn_dir")"
    for tpg_dir in "$iqn_dir"/tpgt_*; do
      [[ -d "$tpg_dir" ]] || continue
      dyn_file="$tpg_dir/dynamic_sessions"
      [[ -r "$dyn_file" ]] || continue
      target_tpg="tpg${tpg_dir##*_}"

      mapfile -t dyn_initiators < <(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$dyn_file" 2>/dev/null | awk 'NF' | sort -u)
      ((${#dyn_initiators[@]} > 0)) || continue
      mapfile -t peers < <(peer_ips_for_tpg "$tpg_dir")

      address=""
      if ((${#dyn_initiators[@]} == 1 && ${#peers[@]} == 1)); then
        address="${peers[0]}"
      fi

      for dyn_initiator in "${dyn_initiators[@]}"; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "dynamic" "" "$dyn_initiator" "LOGGED_IN" "LOGGED_IN" \
          "$address" "TCP" "" "" "rw" "$target_iqn" "$target_tpg"
      done
    done
  done
  shopt -u nullglob
}

parse_targetcli_sessions
parse_dynamic_sessions
