# Анимации из serpantinum

Попапы календаря, Wi-Fi, Bluetooth и музыки из оболочки
[serpantinum](https://github.com/ilyamiro/serpantinum) 2.2.14 (автор — ilyamiro), с правками под
экран 800×480. Это исходники для переноса оболочки AshenOS на Quickshell: сами по себе они не
запускаются, им нужны синглтоны serpantinum (тема, конфиг, MPRIS и т. д.).

Лицензия — GNU AGPL-3.0 (см. [LICENSE.md](LICENSE.md)); при переносе кода она сохраняется.

| Папка | Что внутри |
|---|---|
| `calendar/` | `CalendarPopup.qml`, дата на панели `TimeDateFace.qml` |
| `wifi/` | попап сети `network/*` (там же вкладка Bluetooth), `LoadingDots`, значок `WifiFace.qml` |
| `bluetooth/` | значок `BtFace.qml`, `bluetooth_panel_logic.sh`, карточка `BarBluetoothCard.qml` |
| `music/` | плеер `media/*` (обложка, эквалайзер, текст песен), `WavySeekBar`, `Visualizer`, виджеты музыки |
