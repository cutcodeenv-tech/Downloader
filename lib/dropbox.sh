# Публичные ссылки Dropbox. Папка приходит одним zip-архивом.

download_dropbox() { # url dest_dir
  local url=$1 dest=$2 headers name total
  case $url in
    *dl=0*) url=${url/dl=0/dl=1} ;;
    *dl=1*) ;;
    *\?*)   url="$url&dl=1" ;;
    *)      url="$url?dl=1" ;;
  esac

  headers=$(remote_headers "$url")
  name=$(headers_filename "$headers")
  [ -n "$name" ] || name=$(basename "${url%%\?*}")
  total=$(headers_length "$headers")

  fetch_url "$url" "$dest/$name" "$name" "$total" || die "Не удалось скачать с Dropbox."

  case $name in
    *.zip)
      if [ -t 0 ] && confirm "Пришёл архив $name. Распаковать?"; then
        unzip -q "$dest/$name" -d "$dest" && rm "$dest/$name" && ok "Распаковано."
      fi
      ;;
  esac
}
