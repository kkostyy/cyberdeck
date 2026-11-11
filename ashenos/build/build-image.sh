#!/usr/bin/env bash
# Сборка образа AshenOS для Raspberry Pi 4 (aarch64) на основе Arch Linux ARM.
# Запуск на x86_64 Arch: sudo ./build-image.sh [размер, по умолчанию 8G]
# Нужно: arch-install-scripts, qemu-user-static-binfmt, dosfstools, parted, wget
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
# настройки первого запуска лежат на загрузочном разделе — их можно править с любого компьютера
cp "$ROOT_OVERLAY/boot/ashenos.conf" "$MNT/boot/ashenos.conf"
install -Dm755 "$HERE/ashenos-info" "$MNT/usr/local/bin/ashenos-info"

echo "==> Ставлю приложение Claude (claude-desk)"
APP="$HERE/../apps/claude-desk"
for home in "$MNT/etc/skel" "$MNT/home/alarm"; do
  mkdir -p "$home/.local/share/claude-desk" "$home/.local/state/claude-desk" "$home/claude"
  tar -C "$APP" --exclude=./install.sh --exclude=./README.md -cf - . | tar -C "$home/.local/share/claude-desk" -xf -
  cp "$ROOT_OVERLAY/etc/skel/.local/state/claude-desk/prefs.json" "$home/.local/state/claude-desk/"
done

echo "==> Ставлю пакеты (через qemu, это долго)"
PKGS="$(grep -v '^\s*#' "$HERE/packages.txt" | grep -v '^\s*$' | tr '\n' ' ')"
arch-chroot "$MNT" /bin/bash -e <<CHROOT
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm --needed $PKGS
systemctl enable sddm NetworkManager bluetooth sshd ashenos-firstboot systemd-timesyncd
# сразу применить настройки AshenOS для alarm при первом входе
mkdir -p /home/alarm/.config/ashenos /etc/skel/.config/ashenos
for g in video audio input uucp; do usermod -aG \$g alarm 2>/dev/null || true; done
chown -R alarm:alarm /home/alarm
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
