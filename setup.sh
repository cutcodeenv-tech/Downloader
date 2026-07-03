#!/usr/bin/env bash
# Установка hubdl: зависимости + symlink в ~/.local/bin.
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
say() { printf '%s\n' "$*"; }

# --- зависимости ---
missing=""
for tool in fzf jq; do
  command -v "$tool" >/dev/null || missing="$missing $tool"
done
if ! command -v rclone >/dev/null; then
  say "rclone не найден — он нужен только для загрузок по WebDAV."
  printf 'Установить rclone? (y/n) [y] '
  IFS= read -r answer
  case ${answer:-y} in y|Y|д|Д) missing="$missing rclone" ;; esac
fi

if [ -n "$missing" ]; then
  if command -v brew >/dev/null; then
    say "Устанавливаю:$missing"
    # shellcheck disable=SC2086
    brew install $missing
  else
    say "Homebrew не найден. Установи вручную:$missing"
    exit 1
  fi
fi

# --- команда hubdl ---
chmod +x "$ROOT/bin/hubdl"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$ROOT/bin/hubdl" "$BIN_DIR/hubdl"
say "✔ Команда установлена: $BIN_DIR/hubdl"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.zshrc"
    say "✔ $BIN_DIR добавлен в PATH (~/.zshrc)"
    say "  Перезапусти терминал или выполни: source ~/.zshrc"
    ;;
esac

say ""
say "Готово. Запусти: hubdl"
