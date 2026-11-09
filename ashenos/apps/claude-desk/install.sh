#!/usr/bin/env bash
# Ставит приложение Claude (claude-desk) текущему пользователю.
# Настройки (~/.local/state/claude-desk) не трогает, если они уже есть.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OVERLAY="$HERE/../../airootfs"
DEST="$HOME/.local/share/claude-desk"

mkdir -p "$DEST"
tar -C "$HERE" --exclude=./install.sh --exclude=./README.md -cf - . | tar -C "$DEST" -xf -
if [ ! -f "$HOME/.local/state/claude-desk/prefs.json" ]; then
  install -Dm644 "$OVERLAY/etc/skel/.local/state/claude-desk/prefs.json" "$HOME/.local/state/claude-desk/prefs.json"
fi
install -Dm755 "$OVERLAY/usr/local/bin/claude-console" "$HOME/.local/bin/claude-console"
for f in claude-desk claude-terminal; do
  install -Dm644 "$OVERLAY/usr/share/applications/$f.desktop" "$HOME/.local/share/applications/$f.desktop"
done
install -Dm644 "$OVERLAY/usr/share/icons/hicolor/scalable/apps/claude-desk.svg" \
  "$HOME/.local/share/icons/hicolor/scalable/apps/claude-desk.svg"
[ -f /usr/lib/systemd/user/claude-desk-web.service ] || \
  install -Dm644 "$OVERLAY/usr/lib/systemd/user/claude-desk-web.service" "$HOME/.config/systemd/user/claude-desk-web.service"
mkdir -p "$HOME/claude"
echo "Готово. Запуск: claude-console (или «Claude» в меню)."
echo "Веб-версия (по желанию): systemctl --user enable --now claude-desk-web"
