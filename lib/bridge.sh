# Telegram-мост: агент забирает задачи с bridge-сервера (telegram-bridge-server
# из Editor_hub на VPS) и шлёт обратно прогресс. Протокол совместим с Node-клиентом:
# POST JSON + заголовок x-bridge-secret, эндпоинты /api/internal/*.

BRIDGE_LABEL="com.hubdl.bridge"
BRIDGE_PLIST="$HOME/Library/LaunchAgents/$BRIDGE_LABEL.plist"
BRIDGE_LOG="$HOME/Library/Logs/hubdl-bridge.log"
BRIDGE_PID_FILE="$CONFIG_DIR/bridge.pid"

bridge_post() { # route json_body
  curl -fsS --max-time 10 -X POST \
    -H 'Content-Type: application/json' \
    -H "x-bridge-secret: $BRIDGE_SECRET" \
    -d "$2" "${BRIDGE_URL%/}$1"
}

bridge_state() { # [active_jobs]
  local active=${1:-0} total_kb=0 avail_kb=0 projects
  read -r total_kb avail_kb <<EOF
$(df -k "$DOWNLOAD_ROOT" 2>/dev/null | awk 'NR == 2 { print $2, $4 }')
EOF
  total_kb=${total_kb:-0}; avail_kb=${avail_kb:-0}
  projects=$( (cd "$DOWNLOAD_ROOT" 2>/dev/null && ls -1d ./*/ 2>/dev/null | sed 's#^\./##; s#/$##') |
    while IFS= read -r name; do
      printf '%s\t%s\n' "$(printf '%s' "$name" | shasum | cut -c1-12)" "$name"
    done | jq -Rs 'split("\n") | map(select(length > 0) | split("\t") | {id: .[0], name: .[1]})')
  [ -n "$projects" ] || projects="[]"
  jq -n --arg root "$DOWNLOAD_ROOT" \
    --argjson total $((total_kb * 1024)) --argjson free $((avail_kb * 1024)) \
    --argjson projects "$projects" --argjson active "$active" \
    '{downloadRoot: $root,
      storage: {totalBytes: $total, freeBytes: $free, usedBytes: ($total - $free)},
      projects: $projects, activeJobs: $active, updatedAt: (now | todate)}'
}

bridge_heartbeat() { # [active_jobs]
  bridge_post "/api/internal/agents/heartbeat" "$(jq -n \
    --arg a "$AGENT_ID" --argjson s "$(bridge_state "${1:-0}")" \
    '{agentId: $a, state: $s}')" >/dev/null
}

bridge_snapshot() { # status percent total downloaded speed eta current error completedAt
  jq -n \
    --arg status "$1" --arg project "$BRIDGE_PROJECT" --arg ppath "$BRIDGE_DEST" \
    --arg input "$BRIDGE_SOURCE" \
    --argjson percent "${2:-0}" --argjson total "${3:-0}" \
    --argjson down "${4:-0}" --argjson speed "${5:-0}" \
    --arg eta "${6-}" --arg current "${7-}" --arg error "${8-}" --arg completed "${9-}" \
    '{status: $status, projectName: $project, projectPath: $ppath, remoteInput: $input,
      progressPercent: $percent, totalFiles: 0, completedFiles: 0,
      totalBytes: $total, downloadedBytes: $down, downloadSpeed: $speed,
      etaSeconds: (if $eta == "" then null else ($eta | tonumber) end),
      currentFile: $current,
      error: (if $error == "" then null else $error end),
      fileSummary: {queued: 0, downloading: (if $status == "downloading" then 1 else 0 end), failed: 0, paused: 0},
      storage: null, updatedAt: (now | todate),
      completedAt: (if $completed == "" then null else $completed end)}'
}

bridge_post_status() { # snapshot_json [errorlog_file]
  local body
  if [ -n "${2-}" ] && [ -s "$2" ]; then
    body=$(jq -n --arg a "$AGENT_ID" --arg j "$BRIDGE_JOB_ID" --argjson s "$1" \
      --arg e "$(tail -c 3000 "$2")" '{agentId: $a, jobId: $j, snapshot: $s, errorLog: $e}')
  else
    body=$(jq -n --arg a "$AGENT_ID" --arg j "$BRIDGE_JOB_ID" --argjson s "$1" \
      '{agentId: $a, jobId: $j, snapshot: $s}')
  fi
  bridge_post "/api/internal/tasks/$BRIDGE_TASK_ID/status" "$body" >/dev/null
}

bridge_complete_command() { # command_id result_json
  bridge_post "/api/internal/agents/commands/$1/complete" "$(jq -n \
    --arg a "$AGENT_ID" --argjson r "$2" --argjson s "$(bridge_state 0)" \
    '{agentId: $a, result: $r, state: $s}')" >/dev/null
}

bridge_fail_command() { # command_id error_message
  bridge_post "/api/internal/agents/commands/$1/fail" "$(jq -n \
    --arg a "$AGENT_ID" --arg e "$2" --argjson s "$(bridge_state 0)" \
    '{agentId: $a, error: $e, state: $s}')" >/dev/null
}

bridge_handle_idle_command() {
  local payload cid ctype name
  payload=$(bridge_post "/api/internal/agents/commands/claim" \
    "$(jq -n --arg a "$AGENT_ID" '{agentId: $a}')" 2>/dev/null) || return 0
  cid=$(printf '%s' "$payload" | jq -r '.command.id // empty')
  [ -n "$cid" ] || return 0
  ctype=$(printf '%s' "$payload" | jq -r '.command.type // empty')
  case $ctype in
    delete_project)
      name=$(printf '%s' "$payload" | jq -r '.command.payload.projectName // empty')
      case $name in
        '' | */* | *..*) bridge_fail_command "$cid" "Некорректное имя проекта." 2>/dev/null; return 0 ;;
      esac
      rm -rf "${DOWNLOAD_ROOT:?}/$name"
      say ""
      ok "Удалён проект по команде из Telegram: $name"
      bridge_complete_command "$cid" "$(jq -n --arg n "$name" \
        '{type: "delete_project", projectName: $n, deleted: true}')" 2>/dev/null
      ;;
    cancel_download)
      bridge_fail_command "$cid" "Сейчас нет активной загрузки." 2>/dev/null
      ;;
    *)
      bridge_fail_command "$cid" "Команда не поддерживается: $ctype" 2>/dev/null
      ;;
  esac
}

# Хук из fetch_attempt: раз в секунду. Шлёт статус (раз в 3 c), heartbeat (раз в 10 с),
# проверяет команды (раз в 4 с). Возврат 1 = отмена текущей загрузки.
bridge_tick() { # size total speed
  [ -n "${BRIDGE_TASK_ID-}" ] || return 0
  local size=$1 total=$2 speed=$3 now percent=0 eta=""
  now=$(date +%s)

  if [ $((now - ${BRIDGE_LAST_STATUS:-0})) -ge 3 ]; then
    BRIDGE_LAST_STATUS=$now
    if [ "$total" -gt 0 ] 2>/dev/null; then
      percent=$((size * 100 / total))
      [ "$speed" -gt 0 ] 2>/dev/null && eta=$(((total - size) / speed))
    fi
    bridge_post_status "$(bridge_snapshot downloading "$percent" "$total" "$size" "$speed" \
      "$eta" "${HUBDL_CURRENT_LABEL-}" "" "")" 2>/dev/null
  fi

  if [ $((now - ${BRIDGE_LAST_HB:-0})) -ge 10 ]; then
    BRIDGE_LAST_HB=$now
    bridge_heartbeat 1 2>/dev/null
  fi

  if [ $((now - ${BRIDGE_LAST_CMD:-0})) -ge 4 ]; then
    BRIDGE_LAST_CMD=$now
    local payload cid ctype cjob
    payload=$(bridge_post "/api/internal/agents/commands/claim" \
      "$(jq -n --arg a "$AGENT_ID" '{agentId: $a}')" 2>/dev/null) || return 0
    cid=$(printf '%s' "$payload" | jq -r '.command.id // empty')
    [ -n "$cid" ] || return 0
    ctype=$(printf '%s' "$payload" | jq -r '.command.type // empty')
    cjob=$(printf '%s' "$payload" | jq -r '.command.payload.jobId // empty')
    if [ "$ctype" = "cancel_download" ] && [ "$cjob" = "$BRIDGE_JOB_ID" ]; then
      bridge_complete_command "$cid" "$(jq -n --arg j "$BRIDGE_JOB_ID" \
        '{type: "cancel_download", jobId: $j, cancelled: true}')" 2>/dev/null
      touch "$BRIDGE_DEST/.hubdl-cancelled"
      return 1
    fi
    bridge_fail_command "$cid" "Агент занят загрузкой." 2>/dev/null
  fi
  return 0
}

bridge_run_task() { # task_id project source
  local task_id=$1 project=$2 source=$3 dest status=0 errlog kind

  case $project in
    '' | */* | *..*)
      BRIDGE_TASK_ID=$task_id BRIDGE_JOB_ID="bad-$task_id" BRIDGE_PROJECT=$project
      BRIDGE_SOURCE=$source BRIDGE_DEST=""
      bridge_post_status "$(bridge_snapshot failed 0 0 0 0 "" "" \
        "Некорректное имя проекта." "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" 2>/dev/null
      unset BRIDGE_TASK_ID
      return 0
      ;;
  esac

  dest="$DOWNLOAD_ROOT/$project"
  mkdir -p "$dest"
  errlog="$dest/download-error.log"
  : >"$errlog"

  BRIDGE_TASK_ID=$task_id
  BRIDGE_JOB_ID="$(date +%s)-$$-$RANDOM"
  BRIDGE_PROJECT=$project
  BRIDGE_SOURCE=$source
  BRIDGE_DEST=$dest
  rm -f "$dest/.hubdl-cancelled"

  say ""
  say "${C_BOLD}Задача из Telegram:${C_RESET} $project ← $source"

  bridge_post "/api/internal/tasks/$task_id/attach" "$(jq -n \
    --arg a "$AGENT_ID" --arg j "$BRIDGE_JOB_ID" \
    --argjson s "$(bridge_snapshot downloading 0 0 0 0 "" "" "" "")" \
    '{agentId: $a, jobId: $j, snapshot: $s}')" >/dev/null 2>&1

  kind=$(detect_source "$source")
  (
    HUBDL_TICK_HOOK=bridge_tick
    HUBDL_ASSUME_YES=1
    BRIDGE_LAST_STATUS=0 BRIDGE_LAST_HB=0 BRIDGE_LAST_CMD=0
    dispatch_download "$kind" "$source" "$dest"
  ) 2> >(tee -a "$errlog" >&2) || status=$?

  if [ -f "$dest/.hubdl-cancelled" ]; then
    rm -f "$dest/.hubdl-cancelled"
    warn "Загрузка отменена из Telegram."
    bridge_post_status "$(bridge_snapshot failed 0 0 0 0 "" "" \
      "Отменено из Telegram." "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" 2>/dev/null
  elif [ "$status" -eq 0 ]; then
    ok "Задача выполнена: $project"
    rm -f "$errlog"
    bridge_post_status "$(bridge_snapshot completed 100 0 0 0 "" "" "" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" 2>/dev/null
  else
    fail "Задача завершилась с ошибкой: $project"
    bridge_post_status "$(bridge_snapshot failed 0 0 0 0 "" "" \
      "Ошибка загрузки." "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "$errlog" 2>/dev/null
  fi
  [ -s "$errlog" ] || rm -f "$errlog"
  unset BRIDGE_TASK_ID BRIDGE_JOB_ID BRIDGE_PROJECT BRIDGE_SOURCE BRIDGE_DEST
}

bridge_setup() {
  say "${C_BOLD}Настройка Telegram-моста${C_RESET}"
  BRIDGE_URL=$(ask "Bridge URL (адрес сервера на VPS):" "$BRIDGE_URL")
  BRIDGE_SECRET=$(ask "Bridge secret (BRIDGE_SHARED_SECRET с VPS):" "$BRIDGE_SECRET")
  AGENT_ID=$(ask "Имя агента:" "${AGENT_ID:-$(hostname -s 2>/dev/null || hostname)}")
  save_config
  ok "Сохранено."
}

bridge_running_pid() {
  local pid
  [ -f "$BRIDGE_PID_FILE" ] || return 1
  pid=$(cat "$BRIDGE_PID_FILE" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  printf '%s' "$pid"
}

bridge_worker() {
  local other
  if other=$(bridge_running_pid) && [ "$other" != "$$" ]; then
    warn "Мост уже запущен (PID $other) — второй экземпляр не нужен."
    warn "Остановить фоновый: hubdl bridge disable (или пункт меню)."
    return 0
  fi

  if [ -z "$BRIDGE_URL" ] || [ -z "$BRIDGE_SECRET" ]; then
    if [ -t 0 ]; then
      bridge_setup
    fi
    if [ -z "$BRIDGE_URL" ] || [ -z "$BRIDGE_SECRET" ]; then
      fail "Мост не настроен — запусти hubdl в терминале и заполни Bridge URL и secret."
      sleep 30
      return 1
    fi
  fi
  [ -n "$AGENT_ID" ] || { AGENT_ID=$(hostname -s 2>/dev/null || hostname); save_config; }

  printf '%s' "$$" >"$BRIDGE_PID_FILE"

  say ""
  say "${C_BOLD}Telegram-мост запущен.${C_RESET} Агент: $AGENT_ID → ${BRIDGE_URL%/}"
  [ -t 0 ] && say "${C_DIM}Ctrl-C — остановить мост и вернуться в меню.${C_RESET}"

  BRIDGE_STOP=0
  trap 'BRIDGE_STOP=1' INT TERM

  local last_hb=0 now payload tid tproj tsrc offline=0
  while [ "$BRIDGE_STOP" -eq 0 ]; do
    now=$(date +%s)
    if [ $((now - last_hb)) -ge 10 ]; then
      if bridge_heartbeat 0 2>/dev/null; then
        [ "$offline" -eq 1 ] && { say ""; ok "Связь с мостом восстановлена."; }
        offline=0
      else
        [ "$offline" -eq 0 ] && { say ""; warn "Нет связи с мостом ($BRIDGE_URL) — продолжаю попытки…"; }
        offline=1
      fi
      last_hb=$now
    fi

    if [ "$offline" -eq 0 ]; then
      bridge_handle_idle_command
      payload=$(bridge_post "/api/internal/tasks/claim" \
        "$(jq -n --arg a "$AGENT_ID" '{agentId: $a}')" 2>/dev/null) || payload=""
      tid=$(printf '%s' "$payload" | jq -r '.task.id // empty' 2>/dev/null)
      if [ -n "$tid" ]; then
        tproj=$(printf '%s' "$payload" | jq -r '.task.projectName // empty')
        tsrc=$(printf '%s' "$payload" | jq -r '.task.source // empty')
        bridge_run_task "$tid" "$tproj" "$tsrc"
        continue
      fi
    fi

    # индикатор ожидания — только в живом терминале, чтобы не засорять лог
    [ -t 1 ] && printf '\r%s⌛ ожидание задач из Telegram… %s%s\033[K' "$C_DIM" "$(date +%H:%M:%S)" "$C_RESET"
    sleep 5
  done

  trap - INT TERM
  rm -f "$BRIDGE_PID_FILE"
  say ""
  ok "Мост остановлен."
}

# --- фоновый режим через launchd (macOS) ---

bridge_autostart_enable() {
  if [ -z "$BRIDGE_URL" ] || [ -z "$BRIDGE_SECRET" ]; then
    bridge_setup
    [ -n "$BRIDGE_URL" ] && [ -n "$BRIDGE_SECRET" ] || { warn "Мост не настроен."; return 1; }
  fi
  # launchd не может исполнять скрипты с внешнего диска (защита съёмных томов),
  # поэтому фоновая копия кода живёт локально и обновляется при каждом включении
  local runtime="$HOME/.local/share/hubdl"
  mkdir -p "$runtime"
  rm -rf "$runtime/bin" "$runtime/lib"
  cp -R "$ROOT/bin" "$ROOT/lib" "$runtime/"
  chmod +x "$runtime/bin/hubdl"

  mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$BRIDGE_LOG")"
  cat >"$BRIDGE_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BRIDGE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$runtime/bin/hubdl</string>
    <string>bridge</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$BRIDGE_LOG</string>
  <key>StandardErrorPath</key><string>$BRIDGE_LOG</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)" "$BRIDGE_PLIST" 2>/dev/null
  launchctl enable "gui/$(id -u)/$BRIDGE_LABEL" 2>/dev/null
  if launchctl bootstrap "gui/$(id -u)" "$BRIDGE_PLIST" 2>/dev/null; then
    ok "Автозапуск включён: мост работает в фоне и стартует при входе в систему."
    say "${C_DIM}Лог: $BRIDGE_LOG${C_RESET}"
  else
    fail "launchctl не смог загрузить агент — проверь: launchctl print gui/$(id -u)/$BRIDGE_LABEL"
    return 1
  fi
}

bridge_autostart_disable() {
  launchctl bootout "gui/$(id -u)" "$BRIDGE_PLIST" 2>/dev/null
  rm -f "$BRIDGE_PLIST"
  ok "Автозапуск выключен, фоновый мост остановлен."
}

bridge_status() {
  local pid
  if pid=$(bridge_running_pid); then
    ok "Мост запущен (PID $pid), агент: ${AGENT_ID:-—}."
  else
    warn "Мост сейчас не запущен."
  fi
  if [ -f "$BRIDGE_PLIST" ]; then
    say "Автозапуск: ${C_GREEN}включён${C_RESET}"
  else
    say "Автозапуск: выключен"
  fi
  [ -f "$BRIDGE_LOG" ] && say "${C_DIM}Лог: $BRIDGE_LOG${C_RESET}"
}

bridge_show_log() {
  if [ -f "$BRIDGE_LOG" ]; then
    tail -n 40 "$BRIDGE_LOG" | tr '\r' '\n' | grep -v '^$'
  else
    warn "Лога пока нет."
  fi
}

bridge_menu() {
  while true; do
    local choice
    choice=$(menu "Telegram мост  (Esc — назад)" \
      "Запустить в этом окне" \
      "Автозапуск в фоне: включить" \
      "Автозапуск в фоне: выключить" \
      "Статус" \
      "Показать лог" \
      "← Назад")
    case $choice in
      "Запустить в этом окне")     bridge_worker ;;
      "Автозапуск в фоне: включить")  bridge_autostart_enable ;;
      "Автозапуск в фоне: выключить") bridge_autostart_disable ;;
      "Статус")                    bridge_status ;;
      "Показать лог")              bridge_show_log ;;
      *)                           return 0 ;;
    esac
  done
}
