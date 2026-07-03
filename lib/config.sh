# Настройки: ~/.config/hubdl/config (chmod 600, обычный sourceable-файл).

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hubdl"
CONFIG_FILE="$CONFIG_DIR/config"

DOWNLOAD_ROOT="$HOME/Downloads/hubdl"
WEBDAV_URL="https://webdav.yandex.ru"
WEBDAV_USER=""
WEBDAV_PASS=""
TRANSFERS=2

load_config() {
  # shellcheck disable=SC1090
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  return 0
}

save_config() {
  mkdir -p "$CONFIG_DIR"
  {
    printf 'DOWNLOAD_ROOT=%q\n' "$DOWNLOAD_ROOT"
    printf 'WEBDAV_URL=%q\n' "$WEBDAV_URL"
    printf 'WEBDAV_USER=%q\n' "$WEBDAV_USER"
    printf 'WEBDAV_PASS=%q\n' "$WEBDAV_PASS"
    printf 'TRANSFERS=%q\n' "$TRANSFERS"
  } >"$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

first_run() {
  say "${C_BOLD}Первая настройка hubdl${C_RESET}"
  DOWNLOAD_ROOT=$(ask "Папка, куда складывать проекты:" "$DOWNLOAD_ROOT")
  WEBDAV_URL=$(ask "WebDAV URL:" "$WEBDAV_URL")
  WEBDAV_USER=$(ask "Логин WebDAV (Enter — пропустить):" "")
  if [ -n "$WEBDAV_USER" ]; then
    WEBDAV_PASS=$(ask "Пароль приложения WebDAV:" "")
  fi
  TRANSFERS=$(ask "Одновременных загрузок (WebDAV):" "$TRANSFERS")
  mkdir -p "$DOWNLOAD_ROOT"
  save_config
  ok "Настройки сохранены: $CONFIG_FILE"
}

settings_menu() {
  while true; do
    local choice
    choice=$(menu "Настройки  (Esc — назад)" \
      "Папка проектов        $DOWNLOAD_ROOT" \
      "WebDAV URL            $WEBDAV_URL" \
      "WebDAV логин          ${WEBDAV_USER:-—}" \
      "WebDAV пароль         ${WEBDAV_PASS:+••••••}" \
      "Одновременных загрузок  $TRANSFERS" \
      "← Назад")
    case $choice in
      "Папка проектов"*)  DOWNLOAD_ROOT=$(ask "Папка проектов:" "$DOWNLOAD_ROOT"); mkdir -p "$DOWNLOAD_ROOT" ;;
      "WebDAV URL"*)      WEBDAV_URL=$(ask "WebDAV URL:" "$WEBDAV_URL") ;;
      "WebDAV логин"*)    WEBDAV_USER=$(ask "WebDAV логин:" "$WEBDAV_USER") ;;
      "WebDAV пароль"*)   WEBDAV_PASS=$(ask "Пароль приложения WebDAV:" "") ;;
      "Одновременных"*)   TRANSFERS=$(ask "Одновременных загрузок:" "$TRANSFERS") ;;
      *)                  return 0 ;;
    esac
    save_config
    ok "Сохранено."
  done
}
