# Цвета и примитивы ввода/вывода.

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf '%s✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()  { fail "$*"; exit 1; }

# ask "Вопрос" ["значение по умолчанию"] → ответ в stdout
ask() {
  local prompt=$1 default=${2-} answer
  if [ -n "$default" ]; then
    printf '%s %s[%s]%s ' "$prompt" "$C_DIM" "$default" "$C_RESET" >&2
  else
    printf '%s ' "$prompt" >&2
  fi
  IFS= read -r answer
  printf '%s' "${answer:-$default}"
}

# menu "заголовок" пункт... → выбранный пункт в stdout (пусто при Esc)
menu() {
  local header=$1; shift
  printf '%s\n' "$@" | fzf --reverse --no-info --height=40% --border \
    --prompt='› ' --header="$header"
}

confirm() {
  local answer
  answer=$(ask "$1 (y/n)" "y")
  case $answer in y|Y|yes|д|Д|да) return 0 ;; *) return 1 ;; esac
}
