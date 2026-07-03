# Публичные ссылки Яндекс Диска (disk.yandex.ru / yadi.sk) через Cloud API.
# Папки скачиваются пофайлово рекурсивно — без ограничения на размер zip-архива.

YD_API="https://cloud-api.yandex.net/v1/disk/public/resources"

yd_fetch_file() { # href dest_file label
  say "${C_CYAN}↓${C_RESET} $3"
  curl -fL -# -o "$2" "$1" || die "Не удалось скачать: $3"
}

download_yandex_public() { # url dest_dir
  local url=$1 dest=$2 meta type name href
  meta=$(curl -fsS -G "$YD_API" --data-urlencode "public_key=$url") \
    || die "Яндекс API не ответил. Проверь ссылку (и не запрещено ли скачивание владельцем)."
  type=$(printf '%s' "$meta" | jq -r '.type // empty')
  name=$(printf '%s' "$meta" | jq -r '.name // "download"')
  case $type in
    file)
      href=$(printf '%s' "$meta" | jq -r '.file // empty')
      if [ -z "$href" ]; then
        href=$(curl -fsS -G "$YD_API/download" --data-urlencode "public_key=$url" | jq -r '.href // empty')
      fi
      [ -n "$href" ] || die "Яндекс не отдал ссылку на скачивание."
      yd_fetch_file "$href" "$dest/$name" "$name"
      ;;
    dir)
      mkdir -p "$dest/$name"
      yd_walk "$url" "/" "$dest/$name"
      ;;
    *)
      die "Не удалось разобрать ответ Яндекс Диска: $(printf '%s' "$meta" | jq -r '.message // .error // "неизвестная ошибка"')"
      ;;
  esac
}

yd_walk() { # public_key inner_path dest_dir
  local key=$1 path=$2 dest=$3
  local offset=0 limit=200 page count
  mkdir -p "$dest"
  while true; do
    page=$(curl -fsS -G "$YD_API" \
      --data-urlencode "public_key=$key" \
      --data-urlencode "path=$path" \
      --data-urlencode "limit=$limit" \
      --data-urlencode "offset=$offset") || die "Ошибка листинга папки: $path"
    count=$(printf '%s' "$page" | jq '._embedded.items | length')
    [ "$count" -gt 0 ] || break

    local itype ipath iname ifile
    while IFS=$'\t' read -r itype ipath iname ifile; do
      if [ "$itype" = "dir" ]; then
        yd_walk "$key" "$ipath" "$dest/$iname"
      else
        if [ -z "$ifile" ]; then
          ifile=$(curl -fsS -G "$YD_API/download" \
            --data-urlencode "public_key=$key" \
            --data-urlencode "path=$ipath" | jq -r '.href // empty')
        fi
        [ -n "$ifile" ] || die "Яндекс не отдал ссылку на файл: $iname"
        yd_fetch_file "$ifile" "$dest/$iname" "$path$iname"
      fi
    done < <(printf '%s' "$page" | jq -r '._embedded.items[] | [.type, .path, .name, (.file // "")] | @tsv')

    offset=$((offset + count))
    [ "$count" -lt "$limit" ] && break
  done
}
