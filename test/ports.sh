#!/usr/bin/env bash
# Разбор вывода ss: порт снимается с локального адреса, IPv4 и IPv6 не
# удваиваются, порт находится поиском.
#
# Запуск: test/ports.sh

set -euo pipefail

SCRIPT=$(dirname "$(readlink -f "$0")")/../bin/omarchy-menu-processes
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; kill "$victim" 2>/dev/null || true' EXIT

sleep 30 &
victim=$!

cat >"$tmp/ss" <<SS
#!/usr/bin/env bash
cat <<'OUT'
LISTEN 0 4096  127.0.0.53%lo:53   0.0.0.0:*
LISTEN 0 511         0.0.0.0:3000 0.0.0.0:* users:(("sleep",pid=$victim,fd=20))
LISTEN 0 511            [::]:3000    [::]:* users:(("sleep",pid=$victim,fd=21))
LISTEN 0 511       127.0.0.1:5432 0.0.0.0:* users:(("sleep",pid=$victim,fd=7))
OUT
SS
chmod +x "$tmp/ss"

row=$(PATH="$tmp:$PATH" XDG_RUNTIME_DIR="$tmp" "$SCRIPT" --refresh "$victim" |
  sed 's/\x1b\[[0-9;]*m//g')

[[ $row == *":3000,5432"* ]] || { echo "порты не попали в строку: $row" >&2; exit 1; }

# Ищем по «:5432», а не по «5432»: голое число находится и в чужих командных
# строках, а двоеточие — это уже тег порта.
found=$(PATH="$tmp:$PATH" XDG_RUNTIME_DIR="$tmp" "$SCRIPT" --list ':5432' | cut -f1)
grep -qx "$victim" <<<"$found" || { echo "поиск по порту 5432 не нашёл $victim, нашёл «$found»" >&2; exit 1; }

echo "порты в порядке: $row"
