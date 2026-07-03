# Публичные ссылки Dropbox. Папка приходит одним zip-архивом.

download_dropbox() { # url dest_dir
  local url=$1 dest=$2 newest
  case $url in
    *dl=0*) url=${url/dl=0/dl=1} ;;
    *dl=1*) ;;
    *\?*)   url="$url&dl=1" ;;
    *)      url="$url?dl=1" ;;
  esac
  say "${C_CYAN}↓${C_RESET} Dropbox…"
  (cd "$dest" && curl -fL -# -O -J "$url") || die "Не удалось скачать с Dropbox."

  newest=$(ls -t "$dest" | head -1)
  case $newest in
    *.zip)
      if [ -t 0 ] && confirm "Пришёл архив $newest. Распаковать?"; then
        unzip -q "$dest/$newest" -d "$dest" && rm "$dest/$newest" && ok "Распаковано."
      fi
      ;;
  esac
}
