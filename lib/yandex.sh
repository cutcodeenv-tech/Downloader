# Публичные ссылки Яндекс Диска (disk.yandex.ru / yadi.sk) через Cloud API.
# Папки скачиваются пофайлово рекурсивно — без ограничения на размер zip-архива.

YD_API="https://cloud-api.yandex.net/v1/disk/public/resources"

download_yandex_public() { # url dest_dir
  local url=$1 dest=$2 meta type name href size
  meta=$(curl -fsS -G "$YD_API" --data-urlencode "public_key=$url") \
    || die "Яндекс API не ответил. Проверь ссылку (и не запрещено ли скачивание владельцем)."
  type=$(printf '%s' "$meta" | jq -r '.type // empty')
  name=$(printf '%s' "$meta" | jq -r '.name // "download"')
  case $type in
    file)
      href=$(printf '%s' "$meta" | jq -r '.file // empty')
      size=$(printf '%s' "$meta" | jq -r '.size // empty')
      if [ -z "$href" ]; then
        href=$(curl -fsS -G "$YD_API/download" --data-urlencode "public_key=$url" | jq -r '.href // empty')
      fi
      [ -n "$href" ] || die "Яндекс не отдал ссылку на скачивание."
      fetch_url "$href" "$dest/$name" "$name" "$size" || die "Не удалось скачать: $name"
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

    local itype ipath iname ifile isize
    while IFS=$'\t' read -r itype ipath iname ifile isize; do
      if [ "$itype" = "dir" ]; then
        yd_walk "$key" "$ipath" "$dest/$iname"
      else
        if [ -z "$ifile" ]; then
          ifile=$(curl -fsS -G "$YD_API/download" \
            --data-urlencode "public_key=$key" \
            --data-urlencode "path=$ipath" | jq -r '.href // empty')
        fi
        [ -n "$ifile" ] || die "Яндекс не отдал ссылку на файл: $iname"
        fetch_url "$ifile" "$dest/$iname" "$path$iname" "$isize" || die "Не удалось скачать: $iname"
      fi
    done < <(printf '%s' "$page" | jq -r '._embedded.items[] | [.type, .path, .name, (.file // ""), (.size // "")] | @tsv')

    offset=$((offset + count))
    [ "$count" -lt "$limit" ] && break
  done
}
