# Проверка и установка обновлений из GitHub.
# fetch выполняется в фоне один раз при каждом запуске, сравнение HEAD..origin/main локальное.

UPDATE_AVAILABLE=0

update_check() {
  UPDATE_AVAILABLE=0
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$ROOT" remote get-url origin >/dev/null 2>&1 || return 0

  if [ -z "${UPDATE_FETCHED-}" ]; then
    UPDATE_FETCHED=1
    ( git -C "$ROOT" fetch --quiet origin main 2>/dev/null & )
  fi

  local behind
  behind=$(git -C "$ROOT" rev-list --count HEAD..origin/main 2>/dev/null) || behind=0
  case $behind in '' | *[!0-9]*) behind=0 ;; esac
  UPDATE_AVAILABLE=$behind
}

update_run() {
  say "${C_CYAN}⬆${C_RESET} Обновляю hubdl из GitHub…"
  if ! git -C "$ROOT" pull --ff-only origin main; then
    fail "Не удалось обновиться автоматически (возможно, есть локальные правки)."
    say "Попробуй вручную: git -C \"$ROOT\" pull"
    return 1
  fi
  ok "Обновлено: $(git -C "$ROOT" log -1 --format='%h %s')"

  # если включён фоновый мост — обновляем его локальную копию и перезапускаем
  if [ -f "$BRIDGE_PLIST" ]; then
    say "Обновляю фоновый мост…"
    if bridge_autostart_enable >/dev/null 2>&1; then
      ok "Фоновый мост перезапущен на новой версии."
    else
      warn "Не удалось перезапустить фоновый мост — сделай это вручную: hubdl bridge enable"
    fi
  fi
}
