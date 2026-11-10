#!/usr/bin/env bash
# Попробовать оболочку AshenOS вместо serpantinum. Повторный запуск возвращает serpantinum.
A="$(cd "$(dirname "$0")" && pwd)/shell.qml"
if pgrep -f "^quickshell -p $A" >/dev/null; then
  pkill -f "^quickshell -p $A"
  command -v serpantinumd >/dev/null && swaymsg exec serpantinumd start >/dev/null
  notify-send -a AshenOS "AshenOS" "Вернул serpantinum" 2>/dev/null
else
  command -v serpantinumd >/dev/null && serpantinumd stop >/dev/null 2>&1
  swaymsg exec "quickshell -p $A" >/dev/null
  notify-send -a AshenOS "AshenOS" "Оболочка AshenOS запущена. Ещё раз try.sh — вернуть serpantinum" 2>/dev/null
fi
