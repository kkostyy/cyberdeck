# Claude (claude-desk)

Окно для Claude Code на Quickshell, под экран 800×480. Внутри работает обычный
`claude` в режиме `stream-json`, так что доступны те же модели, скиллы и разрешения.

- чат с потоковыми ответами, карточки разрешений «Разрешить / Всегда / Отклонить»
- режимы: спрашивать, править самому, план
- модель и глубина размышлений (`Ctrl+M`)
- история чатов (`Ctrl+H`), поиск по чату (`Ctrl+F`)
- скиллы, свои агенты и память `CLAUDE.md` (`Ctrl+K` или `/skills`)
- картинки: вставка из буфера, файл, скриншот области
- шаблоны, задания по расписанию, уведомления (в т. ч. на телефон через ntfy)
- веб-зеркало на 127.0.0.1:8765 (служба `claude-desk-web`, открывать через SSH-туннель)

Тема чёрная, в цветах AshenOS. Если стоит serpantinum с matugen, цвета берутся из обоев.

## Установка

В образе AshenOS уже стоит. Вручную, текущему пользователю:

```bash
sudo pacman -S --needed quickshell python ttf-iosevka-nerd wl-clipboard libnotify libcanberra curl jq
./install.sh
claude-console          # или «Claude» в меню
```

Код ставится в `~/.local/share/claude-desk`, настройки лежат в `~/.local/state/claude-desk`.
