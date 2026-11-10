# AshenOS

**AshenOS** — дистрибутив на базе **Arch Linux ARM** для кибердека на Raspberry Pi 4
(экран Waveshare 4,3" DSI 800×480, клавиатура Rii mini X1). Чёрная тема, sway на Wayland,
оболочка на Quickshell с «жидкими» панелями из рамки, Dynamic Island и экранной клавиатурой.

![Рабочий стол](design/screens/02-desktop.jpg)

## Что внутри

| | |
|---|---|
| База | Arch Linux ARM (aarch64), ядро `linux-rpi` |
| Окружение | sway (Wayland) + своя оболочка на Quickshell ([`shell/ashen`](shell/ashen)): рамка, остров, капли, док, виджеты; вход автологином на tty1 |
| Тема | цветовая схема `AshenOS` (чёрная) для Qt/KDE-приложений, шрифты Iosevka Nerd, Inter и JetBrains Mono |
| Анимации | «жидкие» капли из рамки по кривым прототипа; попапы serpantinum для справки — в `shell/animations` |
| Ввод | клавиатура Rii mini X1; экранная клавиатура — в планах (сейчас ставится отдельно) |
| Экран | оверлей `vc4-kms-dsi-waveshare-800x480`, автоопределение выключено |
| Сеть | NetworkManager, Bluetooth (bluez), SSH, WayVNC |
| Терминал | Konsole + `claude` (Claude Code) из npm, приложение-оболочка «Claude» с питомцем |
| Claude | приложение [claude-desk](apps/claude-desk): Claude Code в окне, скиллы, агенты, история |

## Скриншоты концепта оболочки

| | |
|---|---|
| ![Экран блокировки](design/screens/01-lock.jpg) Экран блокировки: пароль, PIN-код или лицо | ![Календарь](design/screens/03-calendar.jpg) Календарь и погода из рамки |
| ![Музыка](design/screens/04-music.jpg) Плеер с эквалайзером | ![Сеть](design/screens/05-network.jpg) Wi-Fi и Bluetooth |
| ![Клавиатура](design/screens/06-keyboard.jpg) Экранная клавиатура | ![Параметры](design/screens/07-settings.jpg) Параметры системы |
| ![Claude](design/screens/08-claude.jpg) Claude — оболочка над `claude` в терминале и питомец Уголёк на рабочем столе | |

Исходники интерактивного прототипа лежат в [`design/prototype`](design/prototype)
(`System.dc.html` — вся система: блокировка → рабочий стол → окна). Это макет интерфейса,
он открывается в Claude Design, а не напрямую в браузере.

## Структура

```
ashenos/
├── build/
│   ├── build-image.sh   сборка .img для SD-карты
│   ├── packages.txt     список пакетов
│   ├── apply-on-sway.sh AshenOS поверх sway, без Plasma
│   └── ashenos-info     команда: версия, ядро, температура
├── apps/claude-desk/     приложение Claude (Quickshell) + install.sh
├── shell/animations/    попапы календаря, Wi-Fi, Bluetooth и музыки для будущей оболочки
├── airootfs/            файлы, которые накладываются на систему
│   ├── etc/os-release, hostname, motd, issue
│   ├── etc/sddm.conf.d/ashenos.conf
│   ├── etc/xdg/kdeglobals, kwinrc
│   ├── usr/share/color-schemes/AshenOS.colors
│   ├── usr/local/bin/claude-console   кнопка/команда запуска Claude
│   └── boot/config-ashenos.txt   дописывается в /boot/config.txt
└── design/              скриншоты и исходники прототипа
```

## Сборка образа

На компьютере с Arch Linux (x86_64):

```bash
sudo pacman -S --needed arch-install-scripts qemu-user-static-binfmt dosfstools parted wget git
cd ashenos/build
sudo ./build-image.sh 8G
sudo dd if=out/ashenos-rpi4-*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Скрипт скачивает Arch Linux ARM для Pi 4, размечает образ (boot 512 МБ + root ext4),
накладывает `airootfs`, ставит пакеты, оболочку AshenOS (`shell/ashen` с её конфигом sway) и приложение
Claude через qemu-chroot и включает `NetworkManager`, `bluetooth`, `sshd`. При первой загрузке корневой
раздел сам растягивается на всю карту, а если Claude ещё не вошёл в аккаунт — придёт подсказка. Разделы монтируются по меткам (`ASHEN_BOOT`, `ashenos`). Пользователь — `alarm`, вход автоматический. Стандартный пароль `alarm` действует один раз:
при первом входе (в том числе по SSH) система попросит придумать новый. Вход под `root` закрыт, есть `sudo`.

## Установка поверх уже работающего Arch Linux ARM

```bash
git clone https://github.com/kkostyy/cyberdeck && cd cyberdeck/ashenos
sudo pacman -Syu --needed $(grep -v '^\s*#' build/packages.txt | grep -v '^\s*$')
sudo cp -r airootfs/etc airootfs/usr /
sudo sh -c 'cat airootfs/boot/config-ashenos.txt >> /boot/config.txt'
sudo install -Dm755 build/ashenos-info /usr/local/bin/ashenos-info
apps/claude-desk/install.sh          # приложение Claude для текущего пользователя
sudo systemctl enable --now NetworkManager bluetooth
# оболочка AshenOS: файлы и конфиг sway (старый конфиг сохранится как config.pre-ashenos)
mkdir -p ~/.local/share/ashen ~/.config/sway && cp -a shell/ashen/. ~/.local/share/ashen/
[ -f ~/.config/sway/config ] && mv ~/.config/sway/config ~/.config/sway/config.pre-ashenos
cp shell/ashen/sway/config ~/.config/sway/config
sudo ln -sf ~/.local/share/ashen/bin/ashen /usr/local/bin/ashen
```

После перезагрузки автологин на tty1 запустит sway с оболочкой. Если у вас уже есть свой sway
и оболочка (например, serpantinum), вместо замены конфига можно переключаться командой
`shell/ashen/bin/ashen-default on|off`.

## Если на Pi осталась Plasma

Ранние версии AshenOS ставили Plasma 6. Если sway с панелью уже работает, скрипт удалит Plasma,
KWin и SDDM, оставив Konsole, Dolphin и всё, что нужно sway, и поставит оформление AshenOS:

```bash
bash ashenos/build/apply-on-sway.sh
```

Перед изменениями скрипт сохраняет оригиналы файлов и список пакетов в `/var/backups/ashenos-pre/`.
Вход по-прежнему через автологин на tty1 с запуском sway.

## Статус

- [x] Концепт оболочки: рамка, Dynamic Island, капли-панели, виджеты, док, экран блокировки
- [x] Цветовая схема, оверлей экрана, автологин в sway
- [x] Скрипт сборки образа
- [x] Приложение Claude (claude-desk) в образе
- [x] Оболочка из прототипа на Quickshell: рамка, остров, капли, док, виджеты, уведомления, блокировка, настройки
- [ ] Экран блокировки в стиле прототипа (вход — автологин, блокировка — serpantinum)
