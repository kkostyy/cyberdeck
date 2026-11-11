//@ pragma UseQApplication
// AshenOS — Dynamic Island для Plasma 6 (Quickshell).
// Пилюля сверху по центру: часы, музыка (MPRIS), громкость (PipeWire), батарея (UPower),
// таймер и полка для файлов (перетащите файл из Dolphin на остров, потом вытащите куда нужно).
// Наведение или щелчок раскрывают остров. Управление из терминала:
//   quickshell ipc -p /usr/share/ashenos/island call island toggle
//   quickshell ipc -p /usr/share/ashenos/island call island timer 25
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

ShellRoot {
    id: root

    // ---------- состояние ----------
    property bool expanded: false
    property bool pinned: false            // раскрыт щелчком (не закрывается, пока мышь ушла)
    property string osd: ""                // "vol" — краткий показ громкости
    property var shelf: []                 // [{url, name}]
    property int timerLeft: 0              // секунды
    property int timerTotal: 0
    property bool timerRun: false

    // ---------- музыка ----------
    readonly property var player: {
        const ps = Mpris.players.values;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length ? ps[0] : null;
    }
    readonly property bool hasMusic: player !== null && (player.trackTitle || "") !== ""

    // ---------- громкость ----------
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    property real lastVol: -1
    onVolumeChanged: {
        if (lastVol >= 0 && Math.abs(volume - lastVol) > 0.004) { osd = "vol"; osdTimer.restart(); }
        lastVol = volume;
    }
    Timer { id: osdTimer; interval: 1600; onTriggered: root.osd = "" }

    // ---------- батарея ----------
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery
    readonly property int batPct: hasBattery ? Math.round(battery.percentage * 100) : 0

    // ---------- таймер ----------
    Timer {
        interval: 1000; repeat: true; running: root.timerRun
        onTriggered: {
            root.timerLeft = Math.max(0, root.timerLeft - 1);
            if (root.timerLeft === 0) {
                root.timerRun = false;
                done.running = true;
                notify.running = true;
            }
        }
    }
    Process { id: notify; command: ["notify-send", "-a", "Остров", "-i", "chronometer", "Таймер", "Время вышло"] }
    Process { id: done; command: ["canberra-gtk-play", "-i", "complete"] }
    function startTimer(min) { timerTotal = min * 60; timerLeft = timerTotal; timerRun = true; }
    function fmt(s) { const m = Math.floor(s / 60); return m + ":" + String(s % 60).padStart(2, "0"); }

    // ---------- тема: акцент из kdeglobals (его пишет ashenos-settings) ----------
    property color accent: "#f2f2f4"
    readonly property color pillBg: "#050506"
    readonly property color card: "#161619"
    readonly property color txt: "#f2f2f4"
    readonly property color sub: "#a1a1a8"
    FileView {
        path: Quickshell.env("HOME") + "/.config/kdeglobals"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^AccentColor=(\d+),(\d+),(\d+)/m);
            if (m) root.accent = Qt.rgba(m[1] / 255, m[2] / 255, m[3] / 255, 1);
        }
    }

    // ---------- полка ----------
    function addUrls(urls) {
        const next = shelf.slice();
        for (let i = 0; i < urls.length; i++) {
            const u = String(urls[i]);
            if (next.some(f => f.url === u)) continue;
            next.push({ url: u, name: decodeURIComponent(u.split("/").pop()) });
        }
        shelf = next;
    }
    function removeAt(i) { const n = shelf.slice(); n.splice(i, 1); shelf = n; }

    IpcHandler {
        target: "island"
        function toggle(): void { root.pinned = !root.pinned; root.expanded = root.pinned; }
        function timer(minutes: int): void { root.startTimer(minutes); }
        function stopTimer(): void { root.timerRun = false; root.timerLeft = 0; }
        function clearShelf(): void { root.shelf = []; }
    }

    // ---------- окно на каждом экране ----------
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: 260
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "ashen-island"
            // окно пропускает щелчки везде, кроме самого острова
            mask: Region { item: island }

            // размеры пилюли в каждом состоянии
            readonly property bool big: root.expanded || dropHover.containsDrag
            readonly property int pillW: big ? Math.min(420, win.width - 24)
                : root.osd === "vol" ? 230
                : root.timerRun ? 200
                : root.hasMusic ? 250
                : root.shelf.length ? 170 : 140
            readonly property int pillH: big ? (dropHover.containsDrag ? 120 : contentCol.implicitHeight + 28) : 32

            Rectangle {
                id: island
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                width: win.pillW
                height: win.pillH
                radius: win.big ? 26 : 16
                color: root.pillBg
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                clip: true
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
                Behavior on radius { NumberAnimation { duration: 300 } }

                HoverHandler {
                    id: hov
                    onHoveredChanged: {
                        if (hovered) { closeTimer.stop(); openTimer.restart(); }
                        else { openTimer.stop(); if (!root.pinned) closeTimer.restart(); }
                    }
                }
                Timer { id: openTimer; interval: 260; onTriggered: root.expanded = true }
                Timer { id: closeTimer; interval: 420; onTriggered: root.expanded = false }
                TapHandler { onTapped: { root.pinned = !root.pinned; root.expanded = root.pinned || hov.hovered; } }

                DropArea {
                    id: dropHover
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: (drop) => { if (drop.hasUrls) { root.addUrls(drop.urls); drop.acceptProposedAction(); } }
                }

                // ----- свёрнутый вид -----
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 8
                    visible: !win.big
                    opacity: win.big ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    // громкость
                    Text { visible: root.osd === "vol"; text: root.muted ? "🔇" : "🔊"; color: root.txt; font.pixelSize: 13 }
                    Rectangle {
                        visible: root.osd === "vol"
                        Layout.fillWidth: true; height: 5; radius: 3; color: Qt.rgba(1, 1, 1, 0.15)
                        Rectangle { width: parent.width * Math.min(1, root.volume); height: parent.height; radius: 3; color: root.accent
                            Behavior on width { NumberAnimation { duration: 120 } } }
                    }
                    Text { visible: root.osd === "vol"; text: Math.round(root.volume * 100) + "%"; color: root.sub; font.pixelSize: 12; font.family: "Inter" }

                    // таймер
                    Text { visible: root.osd === "" && root.timerRun; text: "⏱"; color: root.accent; font.pixelSize: 13 }
                    Text { visible: root.osd === "" && root.timerRun; text: root.fmt(root.timerLeft); color: root.txt; font.pixelSize: 13; font.family: "Inter"; font.weight: Font.DemiBold; Layout.fillWidth: true }

                    // музыка
                    Rectangle {
                        visible: root.osd === "" && !root.timerRun && root.hasMusic
                        width: 20; height: 20; radius: 6; color: root.card; clip: true
                        Image { anchors.fill: parent; source: root.player ? (root.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop }
                    }
                    Text {
                        visible: root.osd === "" && !root.timerRun && root.hasMusic
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: root.player ? root.player.trackTitle : ""
                        color: root.txt; font.pixelSize: 13; font.family: "Inter"; font.weight: Font.DemiBold
                    }
                    Row {
                        visible: root.osd === "" && !root.timerRun && root.hasMusic && root.player && root.player.isPlaying
                        spacing: 2
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                width: 3; radius: 1.5; color: root.accent; anchors.bottom: parent.bottom
                                height: 6
                                SequentialAnimation on height {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 14; duration: 260 + index * 70 }
                                    NumberAnimation { to: 5; duration: 260 + index * 70 }
                                }
                            }
                        }
                    }

                    // по умолчанию — часы, батарея и полка
                    Text {
                        visible: root.osd === "" && !root.timerRun && !root.hasMusic
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatTime(clock.date, "hh:mm")
                        color: root.txt; font.pixelSize: 13; font.family: "Inter"; font.weight: Font.DemiBold
                    }
                    Text {
                        visible: root.osd === "" && root.shelf.length > 0
                        text: "▤ " + root.shelf.length; color: root.accent; font.pixelSize: 12; font.family: "Inter"
                    }
                    Text {
                        visible: root.osd === "" && root.hasBattery && !root.timerRun && !root.hasMusic
                        text: root.batPct + "%"; color: root.batPct <= 15 ? "#ff6b6b" : root.sub; font.pixelSize: 11.5; font.family: "Inter"
                    }
                }

                // ----- перетаскивание файла на остров -----
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: dropHover.containsDrag
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "⇩"; color: root.accent; font.pixelSize: 26 }
                    Text { text: "Отпустите — файл ляжет на полку"; color: root.txt; font.pixelSize: 13; font.family: "Inter" }
                }

                // ----- раскрытый вид -----
                ColumnLayout {
                    id: contentCol
                    visible: win.big && !dropHover.containsDrag
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 12

                    // музыка
                    RowLayout {
                        visible: root.hasMusic
                        spacing: 12
                        Rectangle {
                            width: 52; height: 52; radius: 12; color: root.card; clip: true
                            Image { anchors.fill: parent; source: root.player ? (root.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.player ? root.player.trackTitle : ""; color: root.txt; font.pixelSize: 14; font.family: "Inter"; font.weight: Font.DemiBold }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.player ? (root.player.trackArtist || root.player.identity) : ""; color: root.sub; font.pixelSize: 12; font.family: "Inter" }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.14)
                                Rectangle {
                                    height: parent.height; radius: 2; color: root.accent
                                    width: root.player && root.player.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                                }
                            }
                        }
                        Row {
                            spacing: 4
                            IslandBtn { glyph: "⏮"; onClicked: if (root.player) root.player.previous() }
                            IslandBtn { glyph: root.player && root.player.isPlaying ? "⏸" : "▶"; big: true; onClicked: if (root.player) root.player.togglePlaying() }
                            IslandBtn { glyph: "⏭"; onClicked: if (root.player) root.player.next() }
                        }
                    }
                    // MPRIS не шлёт позицию сам — обновляем раз в секунду
                    Timer { interval: 1000; repeat: true; running: win.big && root.hasMusic; onTriggered: if (root.player) root.player.positionChanged() }

                    // громкость
                    RowLayout {
                        visible: root.sink !== null
                        spacing: 10
                        IslandBtn { glyph: root.muted ? "🔇" : "🔊"; onClicked: if (root.sink) root.sink.audio.muted = !root.sink.audio.muted }
                        Rectangle {
                            id: volBar
                            Layout.fillWidth: true; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.14)
                            Rectangle { width: parent.width * Math.min(1, root.volume); height: parent.height; radius: 3; color: root.accent }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -8
                                function setAt(x) { if (root.sink) root.sink.audio.volume = Math.max(0, Math.min(1, (x - 8) / volBar.width)); }
                                onPressed: (m) => setAt(m.x)
                                onPositionChanged: (m) => { if (pressed) setAt(m.x); }
                            }
                        }
                        Text { text: Math.round(root.volume * 100) + "%"; color: root.sub; font.pixelSize: 12; font.family: "Inter"; Layout.preferredWidth: 36 }
                    }

                    // таймер
                    RowLayout {
                        spacing: 8
                        Text { text: root.timerRun || root.timerLeft > 0 ? "Таймер " + root.fmt(root.timerLeft) : "Таймер"; color: root.txt; font.pixelSize: 13; font.family: "Inter"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Repeater {
                            model: [5, 15, 25]
                            IslandChip { required property int modelData; label: modelData + " мин"; onClicked: root.startTimer(modelData) }
                        }
                        IslandChip { visible: root.timerRun; label: "Стоп"; onClicked: { root.timerRun = false; root.timerLeft = 0; } }
                    }

                    // полка
                    ColumnLayout {
                        spacing: 6
                        RowLayout {
                            Text { text: "Полка"; color: root.txt; font.pixelSize: 13; font.family: "Inter"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                            IslandChip { visible: root.shelf.length > 0; label: "Очистить"; onClicked: root.shelf = [] }
                        }
                        Text {
                            visible: root.shelf.length === 0
                            text: "Перетащите сюда файл из Dolphin, чтобы отложить его"; color: root.sub; font.pixelSize: 12; font.family: "Inter"
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 6
                            Repeater {
                                model: root.shelf
                                Rectangle {
                                    id: chip
                                    required property var modelData
                                    required property int index
                                    width: Math.min(180, nameT.implicitWidth + 40); height: 30; radius: 10; color: root.card
                                    Drag.active: dragArea.drag.active
                                    Drag.dragType: Drag.Automatic
                                    Drag.supportedActions: Qt.CopyAction
                                    Drag.mimeData: ({ "text/uri-list": chip.modelData.url })
                                    Text { id: nameT; anchors.verticalCenter: parent.verticalCenter; x: 10; width: parent.width - 34; elide: Text.ElideMiddle; text: chip.modelData.name; color: root.txt; font.pixelSize: 12; font.family: "Inter" }
                                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: 9; text: "✕"; color: root.sub; font.pixelSize: 11
                                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.removeAt(chip.index) } }
                                    MouseArea { id: dragArea; anchors.fill: parent; anchors.rightMargin: 26; drag.target: chip; onReleased: chip.x = chip.x }
                                }
                            }
                        }
                    }
                    Item { height: 2 }
                }
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    component IslandBtn: Rectangle {
        id: b
        property string glyph: ""
        property bool big: false
        signal clicked()
        width: big ? 38 : 30; height: width; radius: width / 2
        color: m.pressed ? Qt.rgba(1, 1, 1, 0.22) : m.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : (big ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
        Text { anchors.centerIn: parent; text: b.glyph; color: "#f2f2f4"; font.pixelSize: b.big ? 16 : 13 }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    component IslandChip: Rectangle {
        id: c
        property string label: ""
        signal clicked()
        width: lt.implicitWidth + 20; height: 26; radius: 13
        color: cm.pressed ? Qt.rgba(1, 1, 1, 0.2) : cm.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.07)
        Text { id: lt; anchors.centerIn: parent; text: c.label; color: "#f2f2f4"; font.pixelSize: 12; font.family: "Inter"; font.weight: Font.Medium }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: c.clicked() }
    }
}
