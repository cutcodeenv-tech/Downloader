#!/usr/bin/env bash
# Удаление hubdl: symlink и (по желанию) настройки.
set -eu

rm -f "$HOME/.local/bin/hubdl"
printf '✔ Команда hubdl удалена\n'

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hubdl"
if [ -d "$CONFIG_DIR" ]; then
  printf 'Удалить настройки (%s)? (y/n) [n] ' "$CONFIG_DIR"
  IFS= read -r answer
  case ${answer:-n} in
    y|Y|д|Д) rm -rf "$CONFIG_DIR"; printf '✔ Настройки удалены\n' ;;
  esac
fi

printf 'Готово. Папку проекта можно удалить вручную.\n'
