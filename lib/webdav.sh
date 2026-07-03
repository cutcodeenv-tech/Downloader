# WebDAV (Яндекс Диск по логину/паролю приложения) через rclone.
# rclone используется «на лету», без rclone config.

download_webdav() { # path_or_url dest_dir
  local path=$1 dest=$2 obscured
  command -v rclone >/dev/null || die "Для WebDAV нужен rclone: brew install rclone"
  [ -n "$WEBDAV_URL" ] || die "Сначала укажи WebDAV URL в настройках."
  [ -n "$WEBDAV_USER" ] && [ -n "$WEBDAV_PASS" ] || die "Сначала укажи WebDAV логин и пароль приложения в настройках."

  # полный URL внутри этого WebDAV → относительный путь
  case $path in "$WEBDAV_URL"*) path=${path#"$WEBDAV_URL"} ;; esac
  case $path in /*) ;; *) path="/$path" ;; esac

  obscured=$(rclone obscure "$WEBDAV_PASS")
  rclone copy ":webdav:$path" "$dest" \
    --webdav-url "$WEBDAV_URL" \
    --webdav-user "$WEBDAV_USER" \
    --webdav-pass "$obscured" \
    --progress --transfers "${TRANSFERS:-2}" \
    || die "rclone завершился с ошибкой (проверь путь и логин/пароль приложения)."
}
