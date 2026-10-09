#!/usr/bin/env bash
# Usage: check.sh <index> <host> <port> [<index> <host> <port> ...]
# Checks every server in parallel and prints "<index>\t<exit code>\t<ms>".
# Port 0 means ICMP ping; any other port means a TCP connect.

check() {
  local i=$1 host=${2//[\[\]]/} port=$3 rc ms start out
  if [[ $port != 0 ]]; then
    start=$(date +%s%N)
    timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null
    rc=$?
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
  else
    out=$(ping -c 1 -W 2 -n -- "$host" 2>/dev/null)
    rc=$?
    ms=$(sed -n 's/.*time=\([0-9.]*\).*/\1/p' <<<"$out" | head -n1)
  fi
  printf '%s\t%s\t%s\n' "$i" "$rc" "${ms:-0}"
}

while (( $# >= 3 )); do
  check "$1" "$2" "$3" &
  shift 3
done
wait
