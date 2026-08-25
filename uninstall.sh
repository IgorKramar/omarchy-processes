#!/usr/bin/env bash
#
# Убирает «Процессы» из меню Omarchy и удаляет сам скрипт.
#
#   ./uninstall.sh
#   ./uninstall.sh --dry-run    показать, что было бы сделано

set -Eeuo pipefail

SCRIPT_NAME=omarchy-menu-processes
BIN_DEST="$HOME/.local/bin/$SCRIPT_NAME"
CONFIG_DIR="$HOME/.config/omarchy"
EXTENSION="$CONFIG_DIR/extensions/omarchy-menu.jsonc"
EXTRA="$CONFIG_DIR/menu-extra.jsonc"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/omarchy-menu-processes"

DRY_RUN=0

if [[ -t 1 ]]; then
  C_OK=$'\e[32m' C_WARN=$'\e[33m' C_DIM=$'\e[2m' C_OFF=$'\e[0m'
else
  C_OK='' C_WARN='' C_DIM='' C_OFF=''
fi

log() { printf '%s==>%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
ok() { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
short() { printf '%s' "${1/#$HOME/\~}"; }
have() { command -v "$1" >/dev/null 2>&1; }

run() {
  if ((DRY_RUN)); then
    printf '  %s(dry-run)%s %s\n' "$C_DIM" "$C_OFF" "$*"
    return 0
  fi
  "$@"
}

while (($#)); do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      awk 'NR>2 && /^#/ { sub(/^# ?/, ""); print; next } NR>2 { exit }' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      printf 'неизвестный аргумент: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

log "Убираю пункт меню"
rebuild=0
for target in "$EXTRA" "$EXTENSION"; do
  [[ -f $target ]] || continue
  if grep -q '"system.processes"' "$target"; then
    run cp -a "$target" "$target.bak.$(date +%s)"
    # Пункт занимает одну строку — вместе с комментарием-заголовком над ней,
    # если он оставлен установщиком или руками.
    run sed -i '/"system\.processes"/d' "$target"
    ok "$(short "$target")"
    [[ $target == "$EXTRA" ]] && rebuild=1
  fi
done

if ((rebuild)) && have omarchy-menu-ru; then
  log "Пересобираю меню"
  run omarchy-menu-ru
fi

log "Удаляю скрипт"
if [[ -e $BIN_DEST ]]; then
  run rm -f "$BIN_DEST"
  ok "$(short "$BIN_DEST")"
else
  warn "$(short "$BIN_DEST") уже нет"
fi

[[ -d $STATE_DIR ]] && run rm -rf "$STATE_DIR"

printf '\n%sГотово.%s\n' "$C_OK" "$C_OFF"
