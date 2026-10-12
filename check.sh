#!/usr/bin/env bash
# Usage: check.sh <warn-days> <index> <type> <host> <port> [<index> <type> <host> <port> ...]
#
# Checks every entry in parallel and prints one line per entry:
#   <index>\t<state>\t<value>\t<detail>
# state: 0 = ok, 1 = down / expiring, 2 = unknown
#
#   ping    value = round-trip ms
#   tcp     value = connect time ms
#   http    value = response time ms, detail = HTTP status code (000 = no answer)
#   domain  value = days until the registration expires, detail = expiry date (YYYY-MM-DD)

warn_days=${1:-30}
shift

check_ping() {
  local out ms
  out=$(ping -c 1 -W 2 -n -- "$1" 2>/dev/null) || { printf '1\t0\t'; return; }
  ms=$(sed -n 's/.*time=\([0-9.]*\).*/\1/p' <<<"$out" | head -n1)
  printf '0\t%s\t' "${ms:-0}"
}

check_tcp() {
  local start rc ms
  start=$(date +%s%N)
  timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null
  rc=$?
  ms=$(( ($(date +%s%N) - start) / 1000000 ))
  printf '%s\t%s\t' "$(( rc == 0 ? 0 : 1 ))" "$ms"
}

check_http() {
  local url=$1 out code secs ms
  [[ $url == *://* ]] || url="https://$url"
  out=$(curl -sS -o /dev/null -L --max-redirs 5 --proto =http,https --max-time 10 \
    -w '%{http_code} %{time_total}' -- "$url" 2>/dev/null)
  read -r code secs <<<"${out:-000 0}"
  ms=$(awk -v s="${secs:-0}" 'BEGIN { printf "%d", s * 1000 }')
  if (( 10#${code:-0} >= 200 && 10#${code:-0} < 400 )); then
    printf '0\t%s\t%s' "$ms" "$code"
  else
    printf '1\t%s\t%s' "$ms" "${code:-000}"
  fi
}

# Registration expiry: RDAP first (structured), whois as a fallback for
# registries without RDAP (e.g. .it). Some registries publish no expiry at all.
domain_expiry() {
  local expiry
  expiry=$(curl -sfL --max-time 10 --proto =https -- "https://rdap.org/domain/$1" 2>/dev/null \
    | jq -r 'first(.events[]? | select(.eventAction == "expiration") | .eventDate) // empty' 2>/dev/null)
  if [[ -z $expiry ]] && command -v whois >/dev/null; then
    expiry=$(timeout 15 whois -- "$1" 2>/dev/null \
      | grep -iE '^[[:space:]]*(registry expiry date|registrar registration expiration date|expir(y|ation|e)( date)?|expires( on)?|paid-till|renewal date)[[:space:]]*:' \
      | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+$//')
  fi
  printf '%s' "$expiry"
}

check_domain() {
  local domain=${1#*://} expiry epoch days
  domain=${domain%%/*}
  domain=${domain%%:*}
  domain=${domain,,}

  # A subdomain has no registration of its own: drop leading labels
  # (www.example.co.uk -> example.co.uk) until the registry answers.
  while :; do
    expiry=$(domain_expiry "$domain")
    [[ -n $expiry || $domain != *.*.* ]] && break
    domain=${domain#*.}
  done

  epoch=$(date -d "$expiry" +%s 2>/dev/null)
  if [[ -z $expiry || -z $epoch ]]; then
    printf '2\t0\t'
    return
  fi
  days=$(( (epoch - $(date +%s)) / 86400 ))
  printf '%s\t%s\t%s' "$(( days >= warn_days ? 0 : 1 ))" "$days" "$(date -d "@$epoch" +%F)"
}

check() {
  local i=$1 type=$2 host=${3//[\[\]]/} port=$4 result
  case $type in
    tcp) result=$(check_tcp "$host" "$port") ;;
    http) result=$(check_http "$3") ;;
    domain) result=$(check_domain "$host") ;;
    *) result=$(check_ping "$host") ;;
  esac
  printf '%s\t%s\n' "$i" "$result"
}

while (( $# >= 4 )); do
  check "$1" "$2" "$3" "$4" &
  shift 4
done
wait
