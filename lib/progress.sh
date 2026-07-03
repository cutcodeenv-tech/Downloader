# Загрузка файла с прогрессом: проценты, скорость, ETA.
# curl работает в фоне, строка статуса обновляется раз в секунду.

remote_headers() { curl -fsIL --max-time 20 "$1" 2>/dev/null | tr -d '\r'; }

headers_length() {
  printf '%s\n' "$1" | awk 'tolower($1) == "content-length:" { v = $2 } END { print v }'
}

headers_filename() {
  local h=$1 name
  name=$(printf '%s\n' "$h" | sed -n "s/.*filename\*=[Uu][Tt][Ff]-8''\([^;]*\).*/\1/p" | tail -1)
  if [ -n "$name" ]; then
    # percent-decode (filename*=UTF-8''%D0%9F...)
    printf '%b' "${name//\%/\\x}"
    return 0
  fi
  printf '%s\n' "$1" | sed -n 's/.*filename="\([^"]*\)".*/\1/p' | tail -1
}

remote_content_length() { headers_length "$(remote_headers "$1")"; }

progress_line() { # size total speed_bytes_per_sec
  awk -v s="$1" -v t="$2" -v speed="$3" '
    function hb(b) {
      if (b >= 1073741824) return sprintf("%.2f GB", b / 1073741824)
      if (b >= 1048576)    return sprintf("%.1f MB", b / 1048576)
      if (b >= 1024)       return sprintf("%.0f KB", b / 1024)
      return int(b) " B"
    }
    function ht(x) {
      x = int(x)
      if (x >= 3600) return sprintf("%d:%02d:%02d", x / 3600, (x % 3600) / 60, x % 60)
      return sprintf("%d:%02d", x / 60, x % 60)
    }
    BEGIN {
      if (t + 0 > 0) line = sprintf("  %3d%%  %s / %s", s * 100 / t, hb(s), hb(t))
      else           line = sprintf("  %s", hb(s))
      line = line sprintf("  %s/s", hb(speed))
      if (t + 0 > 0) line = line (speed > 0 ? "  ETA " ht((t - s) / speed) : "  ETA --:--")
      printf "%s", line
    }'
}

finish_line() { # size elapsed_secs
  awk -v s="$1" -v e="$2" -v g="$C_GREEN" -v r="$C_RESET" '
    function hb(b) {
      if (b >= 1073741824) return sprintf("%.2f GB", b / 1073741824)
      if (b >= 1048576)    return sprintf("%.1f MB", b / 1048576)
      if (b >= 1024)       return sprintf("%.0f KB", b / 1024)
      return int(b) " B"
    }
    function ht(x) {
      x = int(x)
      if (x >= 3600) return sprintf("%d:%02d:%02d", x / 3600, (x % 3600) / 60, x % 60)
      return sprintf("%d:%02d", x / 60, x % 60)
    }
    BEGIN {
      avg = e > 0 ? s / e : s
      printf "  %s✔%s %s за %s (%s/s)", g, r, hb(s), ht(e), hb(avg)
    }'
}

# fetch_url <url> <dest_file> <label> [total_bytes]
fetch_url() {
  local url=$1 dest=$2 label=$3 total=${4-}
  case $total in '' | null | *[!0-9]*) total="" ;; esac
  [ -n "$total" ] || total=$(remote_content_length "$url")

  printf '%s↓%s %s\n' "$C_CYAN" "$C_RESET" "$label"
  curl -fsSL -o "$dest" "$url" &
  local pid=$!
  trap 'kill "$pid" 2>/dev/null' INT TERM

  # скорость сглаживается EMA, чтобы ETA не дёргался на секундных провалах
  local start prev_size=0 prev_t size now inst ema=0
  start=$(date +%s); prev_t=$start
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    size=$(wc -c <"$dest" 2>/dev/null | tr -d '[:space:]'); size=${size:-0}
    now=$(date +%s)
    if [ "$now" -gt "$prev_t" ]; then
      inst=$(((size - prev_size) / (now - prev_t)))
      if [ "$ema" -eq 0 ]; then ema=$inst; else ema=$(((ema * 7 + inst * 3) / 10)); fi
    fi
    printf '\r%s\033[K' "$(progress_line "$size" "$total" "$ema")"
    prev_size=$size; prev_t=$now
  done

  local status=0
  wait "$pid" || status=$?
  trap - INT TERM
  if [ "$status" -ne 0 ]; then
    printf '\r\033[K'
    return "$status"
  fi
  size=$(wc -c <"$dest" 2>/dev/null | tr -d '[:space:]'); size=${size:-0}
  now=$(date +%s)
  printf '\r%s\033[K\n' "$(finish_line "$size" $((now - start)))"
}
