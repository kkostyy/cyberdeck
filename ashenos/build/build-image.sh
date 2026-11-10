#!/usr/bin/env bash
# Сборка образа AshenOS для Raspberry Pi 4 (aarch64) на основе Arch Linux ARM.
# Запуск на x86_64 Arch: sudo ./build-image.sh [размер, по умолчанию 8G]
# Нужно: arch-install-scripts, qemu-user-static-binfmt, dosfstools, parted, wget, git
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT_OVERLAY="$HERE/../airootfs"
SIZE="${1:-8G}"
OUT="$HERE/out"
IMG="$OUT/ashenos-rpi4-$(date +%Y.%m.%d)-aarch64.img"
TARBALL="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/$TARBALL"
MNT="$OUT/mnt"

[[ $EUID -eq 0 ]] || { echo "Запустите через sudo"; exit 1; }
mkdir -p "$OUT" "$MNT"

echo "==> Скачиваю Arch Linux ARM"
[[ -f "$OUT/$TARBALL" ]] || wget -O "$OUT/$TARBALL" "$URL"

echo "==> Создаю образ $IMG ($SIZE)"
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"
parted -s "$IMG" mklabel msdos \
  mkpart primary fat32 1MiB 513MiB \
  mkpart primary ext4 513MiB 100%
LOOP="$(losetup --show -fP "$IMG")"
cleanup() { umount -R "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
mkfs.vfat -F32 -n ASHEN_BOOT "${LOOP}p1"
mkfs.ext4 -F -L ashenos "${LOOP}p2"

mount "${LOOP}p2" "$MNT"
mkdir -p "$MNT/boot"
mount "${LOOP}p1" "$MNT/boot"

echo "==> Распаковываю корневую систему"
bsdtar -xpf "$OUT/$TARBALL" -C "$MNT"
# по меткам, а не по mmcblk0/mmcblk1: имя карты зависит от ядра (linux-rpi — mmcblk0)
cat > "$MNT/etc/fstab" <<'FSTAB'
# AshenOS
LABEL=ashenos     /      ext4  defaults,noatime  0 1
LABEL=ASHEN_BOOT  /boot  vfat  defaults          0 2
FSTAB

echo "==> Накладываю файлы AshenOS"
cp -a "$ROOT_OVERLAY/." "$MNT/"
cat "$MNT/boot/config-ashenos.txt" >> "$MNT/boot/config.txt"
rm "$MNT/boot/config-ashenos.txt"
install -Dm755 "$HERE/ashenos-info" "$MNT/usr/local/bin/ashenos-info"

echo "==> Ставлю приложение Claude (claude-desk)"
APP="$HERE/../apps/claude-desk"
for home in "$MNT/etc/skel" "$MNT/home/alarm"; do
  mkdir -p "$home/.local/share/claude-desk" "$home/.local/state/claude-desk" "$home/claude"
  tar -C "$APP" --exclude=./install.sh --exclude=./README.md -cf - . | tar -C "$home/.local/share/claude-desk" -xf -
  cp "$ROOT_OVERLAY/etc/skel/.local/state/claude-desk/prefs.json" "$home/.local/state/claude-desk/"
done

echo "==> Ставлю оболочку serpantinum (sway + Quickshell)"
# desktop/ — настроенная панель AshenOS, если её положили в репозиторий; иначе чистый serpantinum
SERP_TAG=v2.2.14
DESK="$HERE/../desktop"
H="$MNT/home/alarm"
if [[ -d "$DESK/serpantinum/src" ]]; then
  SERP="$DESK/serpantinum"
else
  rm -rf "$OUT/serpantinum"
  git clone --depth 1 --branch "$SERP_TAG" https://github.com/ilyamiro/serpantinum "$OUT/serpantinum"
  SERP="$OUT/serpantinum"
fi
mkdir -p "$H/.local/share/serpantinum" "$H/.local/bin" "$H/.config"
cp -a "$SERP/bin" "$SERP/src" "$H/.local/share/serpantinum/"
[[ -f "$SERP/version.txt" ]] && cp "$SERP/version.txt" "$H/.local/share/serpantinum/"
for b in serpantinum serpantinumd; do
  ln -sf "/home/alarm/.local/share/serpantinum/bin/$b" "$H/.local/bin/$b"
  ln -sf "/home/alarm/.local/share/serpantinum/bin/$b" "$MNT/usr/local/bin/$b"
done
# сначала стандартные конфиги serpantinum, поверх — свои из desktop/home
[[ -d "$SERP/compositors/sway" ]] && mkdir -p "$H/.config/sway" && cp -a "$SERP/compositors/sway/." "$H/.config/sway/"
if [[ -d "$SERP/config" ]]; then
  for c in "$SERP"/config/*; do
    n="$(basename "$c")"
    [[ "$n" == sddm ]] && continue
    mkdir -p "$H/.config/$n" && cp -a "$c/." "$H/.config/$n/"
  done
fi
cp "$ROOT_OVERLAY/etc/skel/.bash_profile" "$H/.bash_profile"
[[ -d "$DESK/home" ]] && cp -a "$DESK/home/." "$H/"
# экран кибердека: 800×480, крупнее в 1.15 раза
if [[ -f "$H/.config/sway/config" ]] && ! grep -q "DSI-1" -r "$H/.config/sway"; then
  printf '\n# AshenOS: экран Waveshare 4,3" DSI\noutput DSI-1 mode 800x480 scale 1.15\n' >> "$H/.config/sway/config"
fi

echo "==> Ставлю пакеты (через qemu, это долго)"
PKGS="$(grep -v '^\s*#' "$HERE/packages.txt" | grep -v '^\s*$' | tr '\n' ' ')"
arch-chroot "$MNT" /bin/bash -e <<CHROOT
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm --needed $PKGS
systemctl enable NetworkManager bluetooth sshd power-profiles-daemon
chown -R alarm:alarm /home/alarm
# стандартный пароль alarm работает один раз: при первом входе (и по SSH) система попросит новый
chage -d 0 alarm
passwd -l root
echo 'alarm ALL=(ALL) ALL' > /etc/sudoers.d/alarm
ln -sf /usr/share/zoneinfo/Europe/Tallinn /etc/localtime
sed -i 's/^#\(ru_RU.UTF-8\)/\1/; s/^#\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo 'LANG=ru_RU.UTF-8' > /etc/locale.conf
npm install -g @anthropic-ai/claude-code || true
pacman -Scc --noconfirm
CHROOT

echo "==> Готово: $IMG"
echo "    Записать на карту: sudo dd if=$IMG of=/dev/sdX bs=4M status=progress conv=fsync"
