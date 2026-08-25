#!/usr/bin/env bash
#
# Ставит «Процессы» — список запущенных процессов для меню Omarchy.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/IgorKramar/omarchy-processes/main/install.sh)
#   ./install.sh                из клона репозитория
#   ./install.sh --no-deps      не доставлять fzf и jq через pacman
#   ./install.sh --dry-run      показать, что было бы сделано
#
# Скрипт идемпотентен: повторный запуск обновляет то, что разошлось, и делает
# бэкап каждого файла, который правит.

set -Eeuo pipefail

REPO=IgorKramar/omarchy-processes
BRANCH=${OMARCHY_PROCESSES_BRANCH:-main}
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

SCRIPT_NAME=omarchy-menu-processes
BIN_DEST="$HOME/.local/bin/$SCRIPT_NAME"
CONFIG_DIR="$HOME/.config/omarchy"
EXTENSION="$CONFIG_DIR/extensions/omarchy-menu.jsonc"
EXTRA="$CONFIG_DIR/menu-extra.jsonc"
ENTRY_ID='"system.processes"'

DRY_RUN=0
WITH_DEPS=1

if [[ -t 1 ]]; then
  C_OK=$'\e[32m' C_WARN=$'\e[33m' C_ERR=$'\e[31m' C_DIM=$'\e[2m' C_OFF=$'\e[0m'
else
  C_OK='' C_WARN='' C_ERR='' C_DIM='' C_OFF=''
fi

log() { printf '%s==>%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
ok() { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die() {
  printf '  %s✗%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2
  exit 1
}
short() { printf '%s' "${1/#$HOME/\~}"; }
have() { command -v "$1" >/dev/null 2>&1; }

run() {
  if ((DRY_RUN)); then
    printf '  %s(dry-run)%s %s\n' "$C_DIM" "$C_OFF" "$*"
    return 0
  fi
  "$@"
}

usage() {
  awk 'NR>2 && /^#/ { sub(/^# ?/, ""); print; next } NR>2 { exit }' "${BASH_SOURCE[0]}"
}

while (($#)); do
  case $1 in
    --no-deps) WITH_DEPS=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "неизвестный аргумент: $1 (см. --help)" ;;
  esac
  shift
done

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Файл из клона рядом с установщиком, а при запуске через curl — из raw.
source_file() {
  local relative=$1 root
  root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || root=""
  if [[ -n $root && -f "$root/$relative" ]]; then
    printf '%s' "$root/$relative"
    return 0
  fi
  local target="$WORK_DIR/${relative//\//_}"
  curl -fsSL "$RAW/$relative" -o "$target" ||
    die "не удалось скачать $relative с $RAW"
  printf '%s' "$target"
}

LAST_BACKUP=""

backup() {
  local file=$1
  [[ -e $file ]] || return 0
  local copy
  copy="$file.bak.$(date +%s)"
  run cp -a "$file" "$copy"
  LAST_BACKUP=$copy
  ok "бэкап: $(short "$copy")"
}

# JSONC меню разбирается оболочкой довольно грубо: строки-комментарии
# выбрасываются, висящие запятые прощаются. Проверяем той же логикой, чтобы
# сломанный файл не оставил пользователя вообще без меню.
menu_parses() {
  local file=$1
  have python3 || return 0
  python3 - "$file" <<'PY'
import json, re, sys
raw = open(sys.argv[1], encoding="utf-8").read()
stripped = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
json.loads(stripped)
PY
}

# Вставляет строку пункта перед последней закрывающей скобкой файла.
insert_entry() {
  local file=$1 entry=$2 tmp="$WORK_DIR/menu.jsonc"
  awk -v entry="$entry" '
    { lines[NR] = $0; if ($0 ~ /^[[:space:]]*}[[:space:]]*$/) last = NR }
    END {
      if (last == 0) { print "нет закрывающей скобки" > "/dev/stderr"; exit 1 }
      for (i = 1; i <= NR; i++) {
        if (i == last) print entry
        print lines[i]
      }
    }
  ' "$file" >"$tmp" || return 1
  run cp "$tmp" "$file"
}

log "Проверяю окружение"
[[ -d $CONFIG_DIR ]] || die "$(short "$CONFIG_DIR") не найден — это не система с Omarchy"
ok "Omarchy: $(short "$CONFIG_DIR")"

missing=()
for tool in fzf jq; do
  have "$tool" || missing+=("$tool")
done
if ((${#missing[@]})); then
  if ((WITH_DEPS)) && have pacman; then
    log "Доставляю зависимости: ${missing[*]}"
    run sudo pacman -S --needed --noconfirm "${missing[@]}" ||
      die "не удалось поставить ${missing[*]} — поставьте вручную и повторите"
  else
    die "нет ${missing[*]} — поставьте их (например, sudo pacman -S --needed ${missing[*]}) и повторите"
  fi
fi
ok "зависимости на месте: fzf, jq"
have hyprctl || warn "hyprctl не найден: список и завершение процессов работают, переключение на окно — нет"

log "Ставлю $SCRIPT_NAME"
src=$(source_file "bin/$SCRIPT_NAME")
if [[ -e $BIN_DEST ]] && cmp -s "$src" "$BIN_DEST"; then
  ok "$(short "$BIN_DEST") — уже актуален"
else
  [[ -e $BIN_DEST ]] && backup "$BIN_DEST"
  run mkdir -p "$(dirname "$BIN_DEST")"
  run install -m 755 "$src" "$BIN_DEST"
  ok "$(short "$BIN_DEST")"
fi
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "$(short "$HOME/.local/bin") не в PATH — меню запускает команды через логин-оболочку, но проверьте свой профиль" ;;
esac

log "Регистрирую пункт меню «Система → Процессы»"
entry=$(cat "$(source_file menu/system.processes.jsonc)")

# Если рядом лежит menu-extra.jsonc (схема omarchy-ru с генератором), пункт
# принадлежит ему: собранное расширение перезапишется при следующей сборке.
if [[ -f $EXTRA ]]; then
  target=$EXTRA
  rebuild=1
else
  target=$EXTENSION
  rebuild=0
  created=0
  if [[ ! -f $target ]]; then
    created=1
    run mkdir -p "$(dirname "$target")"
    if ((DRY_RUN)); then
      printf '  %s(dry-run)%s создал бы %s\n' "$C_DIM" "$C_OFF" "$(short "$target")"
    else
      printf '// Пользовательское расширение меню Omarchy.\n{\n}\n' >"$target"
    fi
    ok "создан $(short "$target")"
  fi
fi

if grep -q "$ENTRY_ID" "$target" 2>/dev/null; then
  ok "$(short "$target") — пункт уже объявлен"
else
  ((${created:-0})) || backup "$target"
  if ((DRY_RUN)); then
    printf '  %s(dry-run)%s добавил бы пункт в %s\n' "$C_DIM" "$C_OFF" "$(short "$target")"
  else
    insert_entry "$target" "$entry" || die "не смог дописать пункт в $(short "$target")"
    if ! menu_parses "$target"; then
      [[ -n $LAST_BACKUP && -e $LAST_BACKUP ]] && cp -a "$LAST_BACKUP" "$target"
      die "после правки $(short "$target") перестал разбираться — вернул бэкап"
    fi
    ok "пункт добавлен в $(short "$target")"
  fi
fi

if ((rebuild)) && have omarchy-menu-ru; then
  log "Пересобираю меню"
  run omarchy-menu-ru ||
    warn "omarchy-menu-ru завершился с ошибкой — пересоберите меню вручную"
fi

printf '\n%sГотово.%s Меню → Система → Процессы, либо команда: omarchy menu summon processes\n' "$C_OK" "$C_OFF"
