# Публичные файлы Google Drive (без API-ключа).
# Папки без авторизации Google не отдаёт — для них нужен rclone с настроенным remote.

download_gdrive() { # url dest_dir
  local url=$1 dest=$2 id="" dl headers name total
  case $url in
    */folders/*) die "Папки Google Drive не поддерживаются без авторизации — скачай файлы по отдельности или настрой rclone (rclone config)." ;;
  esac
  id=$(printf '%s' "$url" | sed -n 's#.*/file/d/\([^/?]*\).*#\1#p')
  [ -n "$id" ] || id=$(printf '%s' "$url" | sed -n 's#.*[?&]id=\([^&]*\).*#\1#p')
  [ -n "$id" ] || die "Не смог извлечь id файла из ссылки Google Drive."

  dl="https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t"
  headers=$(remote_headers "$dl")
  name=$(headers_filename "$headers")
  [ -n "$name" ] || name="gdrive-$id"
  total=$(headers_length "$headers")

  fetch_url "$dl" "$dest/$name" "$name" "$total" \
    || die "Не удалось скачать с Google Drive (файл должен быть доступен по ссылке)."
}
