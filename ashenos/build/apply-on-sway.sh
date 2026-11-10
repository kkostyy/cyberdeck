#!/usr/bin/env bash
# Делает из этой системы AshenOS (на sway + Quickshell, без KDE Plasma):
#   1) удаляет Plasma, SDDM и KWin, но оставляет Konsole, Dolphin и то, что нужно sway/панели;
#   2) ставит оформление AshenOS: имя системы, hostname, приветствие, цветовую схему, ashenos-info, I2C.
# Оригиналы сохраняются в /var/backups/ashenos-pre/.
# Запуск из клона репозитория: bash ashenos/build/apply-on-sway.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
OV="$SRC/airootfs"
BK=/var/backups/ashenos-pre
[ -d "$OV" ] || { echo "Нет $OV — запускайте скрипт из клона репозитория"; exit 1; }

echo "==> Сохраняю оригиналы в $BK"
sudo mkdir -p "$BK"
sudo cp -a /etc/hostname /etc/issue /boot/config.txt "$BK/" 2>/dev/null || true
[ -e /etc/motd ] && sudo cp -a /etc/motd "$BK/"
sudo cp -a /usr/lib/os-release "$BK/os-release"
pacman -Qq > /tmp/pkgs-before.txt && sudo cp /tmp/pkgs-before.txt "$BK/packages-before.txt"

echo "==> Оставляю нужное панели и sway: курсор, Xwayland, эмодзи, I2C, шрифт Hack"
sudo pacman -D --asexplicit breeze-cursors xorg-xwayland noto-fonts-emoji i2c-tools ttf-hack >/dev/null

echo "==> Удаляю KDE Plasma (покажу список и спрошу подтверждение)"
sudo pacman -Rns plasma-desktop plasma-pa kscreen sddm

echo "==> Оформление AshenOS"
sudo rm -f /etc/os-release
sudo install -Dm644 "$OV/etc/os-release" /etc/os-release
sudo install -Dm644 "$OV/etc/motd" /etc/motd
sudo install -Dm644 "$OV/etc/issue" /etc/issue
sudo install -Dm644 "$OV/usr/share/color-schemes/AshenOS.colors" /usr/share/color-schemes/AshenOS.colors
sudo install -Dm755 "$SRC/build/ashenos-info" /usr/local/bin/ashenos-info
sudo hostnamectl hostname ashenos
grep -q "ashenos" /etc/hosts || echo "127.0.1.1        ashenos" | sudo tee -a /etc/hosts >/dev/null

# Экран уже настроен (waveshare-800x480 в config.txt). Добавляю только I2C для OLED.
# gpio-shutdown из AshenOS не ставлю: он висит на GPIO3, а это линия SCL шины I2C.
grep -q "^dtparam=i2c_arm=on" /boot/config.txt || printf '\n# AshenOS: I2C для OLED\ndtparam=i2c_arm=on\n' | sudo tee -a /boot/config.txt >/dev/null

echo
echo "Готово. Plasma удалена, система называется AshenOS:"
ashenos-info
echo
echo "I2C заработает после перезагрузки. Откатить оформление: файлы лежат в $BK"
