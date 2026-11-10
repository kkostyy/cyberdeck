import QtQuick
import QtQuick.Layouts
import Quickshell

// Expanded drop panels: calendar, sound, music, network, app search.
Item {
    id: root
    property string which: ""
    required property var st
    property bool active: false
    signal closeRequested()

    component T: Text {
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.text
        elide: Text.ElideRight
    }
    component G: Text {
        font.family: Theme.icons
        font.pixelSize: 14
        color: Theme.text
    }
    // rounded button; `on` fills it white
    component Btn: Rectangle {
        id: b
        property string glyph: ""
        property string label: ""
        property bool on: false
        signal clicked()
        implicitWidth: label === "" ? 28 : br.implicitWidth + 20
        implicitHeight: 28
        radius: 9
        color: on ? Theme.accent : ma.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
        Behavior on color { ColorAnimation { duration: 160 } }
        scale: ma.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 } }
        RowLayout {
            id: br
            anchors.centerIn: parent
            spacing: 6
            G { visible: b.glyph !== ""; text: b.glyph; font.pixelSize: 13; color: b.on ? Theme.accentInk : Theme.text }
            T { visible: b.label !== ""; text: b.label; font.weight: Font.DemiBold; color: b.on ? Theme.accentInk : Theme.text }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    // horizontal slider 0..1
    component Slider: Item {
        id: sl
        property real value: 0
        signal moved(real v)
        implicitHeight: 22
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                width: parent.width * sl.value; height: parent.height; radius: 3
                color: Theme.accent
            }
        }
        Rectangle {
            x: sl.width * sl.value - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            color: Theme.accent
            scale: sm.pressed ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: 150 } }
        }
        MouseArea {
            id: sm
            anchors.fill: parent
            onPressed: e => sl.moved(Math.max(0, Math.min(1, e.x / width)))
            onPositionChanged: e => { if (pressed) sl.moved(Math.max(0, Math.min(1, e.x / width))); }
        }
    }

    // ── calendar + clock + weather (design/screens/03-calendar.jpg) ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 6
        spacing: 12
        visible: root.which === "clock"

        Rectangle {
            id: cal
            Layout.preferredWidth: 190
            Layout.fillHeight: true
            radius: 12
            color: Theme.cardSolid
            property int offset: 0
            readonly property date month: {
                let d = root.st.clock.date;
                return new Date(d.getFullYear(), d.getMonth() + offset, 1);
            }
            readonly property var cells: {
                let first = (month.getDay() + 6) % 7;      // Monday first
                let days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
                let out = [];
                for (let i = 0; i < first; i++) out.push(0);
                for (let d = 1; d <= days; d++) out.push(d);
                return out;
            }
            readonly property bool thisMonth: offset === 0
            onVisibleChanged: if (visible) offset = 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    G { text: "󰅁"; font.pixelSize: 12; color: Theme.sub; MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: cal.offset-- } }
                    T {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: (Qt.locale("ru_RU").standaloneMonthName(cal.month.getMonth(), Locale.LongFormat) + " " + cal.month.getFullYear()).toUpperCase()
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }
                    G { text: "󰅂"; font.pixelSize: 12; color: Theme.sub; MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: cal.offset++ } }
                }
                Grid {
                    Layout.alignment: Qt.AlignHCenter
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 1
                    Repeater {
                        model: ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
                        T { required property string modelData; width: 24; horizontalAlignment: Text.AlignHCenter; text: modelData; font.pixelSize: 8; color: Theme.dim }
                    }
                    Repeater {
                        model: cal.cells
                        Rectangle {
                            required property int modelData
                            required property int index
                            readonly property bool today: cal.thisMonth && modelData === root.st.clock.date.getDate()
                            width: 24; height: 17; radius: 6
                            color: today ? Theme.accent : "transparent"
                            T {
                                anchors.centerIn: parent
                                text: parent.modelData > 0 ? parent.modelData : ""
                                font.pixelSize: 10
                                font.weight: parent.today ? Font.Bold : Font.Normal
                                color: parent.today ? Theme.accentInk : parent.index % 7 >= 5 ? Theme.dim : Theme.text
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // today's weather on a ring around the clock
        Item {
            id: ring
            Layout.fillWidth: true
            Layout.minimumWidth: 200
            Layout.fillHeight: true
            readonly property var slots: root.st.weather && root.st.weather.ring ? root.st.weather.ring : []
            readonly property real r: Math.min(width, height) / 2 - 18
            Canvas {
                anchors.fill: parent
                onPaint: {
                    let g = getContext("2d");
                    g.reset();
                    if (ring.r <= 0) return;
                    g.strokeStyle = "rgba(255,255,255,0.14)";
                    g.lineWidth = 1;
                    g.setLineDash([2, 4]);
                    g.beginPath();
                    g.arc(width / 2, height / 2, ring.r, 0, Math.PI * 2);
                    g.stroke();
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
            Repeater {
                model: ring.slots
                Rectangle {
                    id: slot
                    required property var modelData
                    required property int index
                    // 12:00 on top, clockwise like a dial
                    readonly property real ang: (parseInt(modelData.t) / 24) * 2 * Math.PI + Math.PI
                    readonly property bool now: Math.floor(root.st.clock.date.getHours() / 3) * 3 === parseInt(modelData.t)
                    x: ring.width / 2 + ring.r * Math.sin(ang) - width / 2
                    y: ring.height / 2 - ring.r * Math.cos(ang) - height / 2
                    width: 34; height: 32; radius: 8
                    color: now ? Qt.rgba(1, 1, 1, 0.22) : Theme.cardSolid
                    border.color: Qt.rgba(1, 1, 1, now ? 0.4 : 0.1)
                    Column {
                        anchors.centerIn: parent
                        spacing: -1
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: slot.modelData.t; font.family: Theme.mono; font.pixelSize: 7; color: Theme.dim }
                        G { anchors.horizontalCenter: parent.horizontalCenter; text: root.st.wmoGlyph(slot.modelData.code, parseInt(slot.modelData.t) >= 6 && parseInt(slot.modelData.t) < 21); font.pixelSize: 9 }
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(slot.modelData.temp) + "°"; font.pixelSize: 8; font.weight: Font.Bold }
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: 1
                T {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(root.st.clock.date, "HH:mm:ss")
                    font.family: Theme.mono
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
                T {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        let s = root.st.clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM");
                        return s.charAt(0).toUpperCase() + s.substring(1);
                    }
                    color: Theme.dim
                    font.pixelSize: 9
                }
            }
        }

        // today
        ColumnLayout {
            Layout.preferredWidth: 150
            Layout.maximumWidth: 150
            Layout.minimumWidth: 150
            Layout.fillHeight: true
            spacing: 4
            readonly property var w: root.st.weather
            T { Layout.alignment: Qt.AlignRight; text: "СЕГОДНЯ"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.8; color: Theme.sub }
            T {
                Layout.alignment: Qt.AlignRight
                text: parent.w ? parent.w.temp.toFixed(1) + "°C" : "—"
                font.family: Theme.mono
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            T { Layout.alignment: Qt.AlignRight; text: parent.w ? parent.w.city : ""; font.weight: Font.Bold }
            T { Layout.alignment: Qt.AlignRight; text: root.st.weatherText; color: Theme.dim; font.pixelSize: 10 }
            Item { Layout.fillHeight: true }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: {
                        let w = root.st.weather;
                        return w ? [
                            { v: Math.round(w.wind) + " м/с", k: "ветер" },
                            { v: w.humidity + "%", k: "влажность" },
                            { v: (w.precip || 0) + "%", k: "осадки" },
                            { v: Math.round(w.feels) + "°", k: "ощущается" }
                        ] : [];
                    }
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: Theme.cardSolid
                        Column {
                            x: 7; anchors.verticalCenter: parent.verticalCenter
                            T { text: parent.parent.modelData.v; font.family: Theme.mono; font.pixelSize: 10; font.weight: Font.Bold }
                            T { text: parent.parent.modelData.k; font.pixelSize: 8; color: Theme.dim }
                        }
                    }
                }
            }
        }
    }

    // ── sound ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        spacing: 8
        visible: root.which === "vol"
        RowLayout {
            Layout.fillWidth: true
            T { text: "Звук и экран"; font.pixelSize: 13; font.weight: Font.Bold }
            T {
                Layout.fillWidth: true
                text: root.st.sink ? (root.st.sink.description || root.st.sink.name) : "нет устройства"
                color: Theme.dim
                horizontalAlignment: Text.AlignRight
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Btn { glyph: root.st.muted ? "󰖁" : "󰕾"; on: root.st.muted; onClicked: root.st.toggleMute() }
            Slider { Layout.fillWidth: true; value: root.st.muted ? 0 : root.st.volume; onMoved: v => root.st.setVolume(v) }
            T { text: Math.round(root.st.volume * 100) + "%"; font.family: Theme.mono; Layout.preferredWidth: 32 }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Btn { glyph: "󰃠" }
            Slider { Layout.fillWidth: true; value: root.st.brightness; onMoved: v => root.st.setBrightness(v) }
            T { text: Math.round(root.st.brightness * 100) + "%"; font.family: Theme.mono; Layout.preferredWidth: 32 }
        }
    }

    // ── system ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        spacing: 6
        visible: root.which === "sys"
        Repeater {
            model: [
                { l: "ЦП", v: root.st.cpu, t: Math.round(root.st.cpu * 100) + "%" },
                { l: "ОЗУ", v: root.st.ram, t: Math.round(root.st.ram * 100) + "%" },
                { l: "Темп.", v: root.st.temp / 85, t: Math.round(root.st.temp) + "°" }
            ]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                T { text: modelData.l; color: Theme.sub; Layout.preferredWidth: 34 }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.1)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, parent.parent.modelData.v))
                        height: parent.height; radius: 4
                        color: parent.parent.modelData.v > 0.85 ? "#ff8a8a" : Theme.accent
                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    }
                }
                T { text: modelData.t; font.family: Theme.mono; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
            }
        }
    }

    // ── clipboard ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 6
        spacing: 4
        visible: root.which === "clip"
        RowLayout {
            Layout.fillWidth: true
            T { text: "Буфер обмена"; font.pixelSize: 13; font.weight: Font.Bold; Layout.fillWidth: true }
            T { text: "клик — скопировать"; color: Theme.dim; font.pixelSize: 9 }
        }
        T {
            visible: root.st.clips.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 20
            horizontalAlignment: Text.AlignHCenter
            text: "Пусто"
            color: Theme.dim
        }
        Repeater {
            model: root.st.clips.slice(0, 6)
            Rectangle {
                id: clip
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 8
                color: cm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.cardSolid
                T {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: Text.AlignVCenter
                    text: clip.modelData.text.replace(/\s+/g, " ")
                    font.family: clip.modelData.text.charAt(0) === "󰋩" ? Theme.icons : Theme.font
                }
                MouseArea {
                    id: cm
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { root.st.pasteClip(clip.modelData.id); root.closeRequested(); }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }

    // ── music ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        spacing: 12
        visible: root.which === "music"
        Rectangle {
            Layout.preferredWidth: 80
            Layout.preferredHeight: 80
            radius: 12
            color: Theme.cardSolid
            clip: true
            Image {
                anchors.fill: parent
                source: root.st.trackArt
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }
            G { anchors.centerIn: parent; text: "󰎆"; font.pixelSize: 28; color: Theme.dim; visible: root.st.trackArt === "" }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            T { Layout.fillWidth: true; text: root.st.trackTitle || "Ничего не играет"; font.pixelSize: 14; font.weight: Font.Bold }
            T { Layout.fillWidth: true; text: root.st.trackArtist; color: Theme.dim }
            Slider {
                Layout.fillWidth: true
                readonly property var p: root.st.player
                value: p && p.length > 0 ? p.position / p.length : 0
                onMoved: v => { if (p && p.canSeek && p.length > 0) p.position = v * p.length; }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Btn { glyph: "󰒮"; onClicked: root.st.player && root.st.player.previous() }
                Btn { glyph: root.st.playing ? "󰏤" : "󰐊"; on: true; onClicked: root.st.player && root.st.player.togglePlaying() }
                Btn { glyph: "󰒭"; onClicked: root.st.player && root.st.player.next() }
            }
        }
    }

    // ── network & Bluetooth (design/screens/05-network.jpg) ──
    Item {
        id: netp
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 4
        visible: root.which === "net" || root.which === "bt"
        property string tab: "wifi"
        property string view: "map"          // map | list (after «Сканировать»)
        property string askFor: ""           // SSID waiting for a password
        onVisibleChanged: if (visible) { tab = root.which === "bt" ? "bt" : "wifi"; view = "map"; askFor = ""; }

        // ── Wi-Fi: the network in the middle, its details on curved wires ──
        Item {
            id: map
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: tabs.top
            anchors.bottomMargin: 6
            visible: netp.tab === "wifi" && netp.view === "map"
            readonly property real cx: width / 2
            readonly property real cy: height / 2
            onSatsChanged: wires.requestPaint()
            readonly property var sats: [
                { x: 0.17, y: 0.18, g: "≋", t: root.st.freq || "—" },
                { x: 0.80, y: 0.10, g: "", t: "Сканировать", btn: true },
                { x: 0.88, y: 0.48, g: "▲", t: root.st.signal + "%" },
                { x: 0.14, y: 0.68, g: "⌂", t: root.st.ip || "нет адреса" },
                { x: 0.62, y: 0.92, g: "◇", t: root.st.security || "открытая" }
            ]
            Canvas {
                id: wires
                anchors.fill: parent
                onPaint: {
                    let g = getContext("2d");
                    g.reset();
                    // soft rings behind the centre
                    for (let i = 3; i >= 1; i--) {
                        g.fillStyle = "rgba(255,255,255," + (0.025 * i) + ")";
                        g.beginPath(); g.arc(map.cx, map.cy, 30 + i * 13, 0, Math.PI * 2); g.fill();
                    }
                    g.strokeStyle = "rgba(255,255,255,0.28)";
                    g.lineWidth = 1;
                    for (let s of map.sats) {
                        let x = s.x * width, y = s.y * height;
                        g.beginPath();
                        g.moveTo(map.cx, map.cy);
                        g.bezierCurveTo(map.cx + (x - map.cx) * 0.2, map.cy + (y - map.cy) * 0.7,
                                        map.cx + (x - map.cx) * 0.8, map.cy + (y - map.cy) * 0.3, x, y);
                        g.stroke();
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
            Repeater {
                model: map.sats
                Rectangle {
                    id: sat
                    required property var modelData
                    x: modelData.x * map.width - width / 2
                    y: modelData.y * map.height - height / 2
                    width: satRow.implicitWidth + 16
                    height: 20
                    radius: 6
                    color: modelData.btn ? (satM.containsMouse ? "#ffffff" : Theme.accent) : Theme.cardSolid
                    border.color: Qt.rgba(1, 1, 1, 0.14)
                    Row {
                        id: satRow
                        anchors.centerIn: parent
                        spacing: 4
                        T { text: sat.modelData.g; font.family: Theme.mono; font.pixelSize: 9; color: sat.modelData.btn ? Theme.accentInk : Theme.sub }
                        T { text: sat.modelData.t; font.family: Theme.mono; font.pixelSize: 9; font.weight: Font.Bold; color: sat.modelData.btn ? Theme.accentInk : Theme.text }
                    }
                    MouseArea {
                        id: satM
                        anchors.fill: parent
                        hoverEnabled: sat.modelData.btn === true
                        enabled: sat.modelData.btn === true
                        onClicked: { root.st.scanWifi(); netp.view = "list"; }
                    }
                }
            }
            Rectangle {
                x: map.cx - width / 2; y: map.cy - height / 2
                width: 64; height: 64; radius: 32
                color: root.st.wifiOn ? "#ececf0" : Theme.cardSolid
                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    G { anchors.horizontalCenter: parent.horizontalCenter; text: root.st.wifiIcon; font.pixelSize: 15; color: root.st.wifiOn ? Theme.accentInk : Theme.text }
                    T { anchors.horizontalCenter: parent.horizontalCenter; width: 58; horizontalAlignment: Text.AlignHCenter; text: root.st.ssid || (root.st.wifiOn ? "нет сети" : "выключен"); font.family: Theme.mono; font.pixelSize: 8; font.weight: Font.Bold; color: root.st.wifiOn ? Theme.accentInk : Theme.text }
                    T { anchors.horizontalCenter: parent.horizontalCenter; text: root.st.ssid ? "подключено" : ""; font.pixelSize: 7; color: "#55555c" }
                }
            }
        }

        // ── Wi-Fi: networks after a scan ──
        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: tabs.top
            anchors.bottomMargin: 6
            visible: netp.tab === "wifi" && netp.view === "list"
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                G { text: "󰅁"; font.pixelSize: 13; color: Theme.sub; MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: { netp.view = "map"; netp.askFor = ""; } } }
                T { Layout.fillWidth: true; text: root.st.scanning ? "Ищу сети…" : "Сети рядом"; font.weight: Font.Bold; font.pixelSize: 12 }
            }
            Repeater {
                model: root.st.networks.slice(0, 5)
                Rectangle {
                    id: nw
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: netp.askFor === modelData.ssid ? 52 : 24
                    radius: 8
                    color: nwm.containsMouse || netp.askFor === modelData.ssid ? Qt.rgba(1, 1, 1, 0.1) : Theme.cardSolid
                    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    clip: true
                    RowLayout {
                        x: 9; width: parent.width - 18; height: 24
                        spacing: 7
                        G { text: nw.modelData.signal > 66 ? "󰤨" : nw.modelData.signal > 33 ? "󰤥" : "󰤟"; font.pixelSize: 12; color: nw.modelData.active ? Theme.accent : Theme.sub }
                        T { Layout.fillWidth: true; text: nw.modelData.ssid; font.weight: nw.modelData.active ? Font.Bold : Font.Normal }
                        G { visible: nw.modelData.secure; text: "󰌾"; font.pixelSize: 10; color: Theme.dim }
                        T { text: nw.modelData.active ? "подключено" : nw.modelData.signal + "%"; color: Theme.dim; font.pixelSize: 9 }
                    }
                    MouseArea {
                        id: nwm
                        width: parent.width; height: 24
                        hoverEnabled: true
                        onClicked: {
                            if (nw.modelData.active) return;
                            // try without a password first (known network); ask for one if it's secured
                            if (nw.modelData.secure) { netp.askFor = nw.modelData.ssid; pass.text = ""; pass.forceActiveFocus(); }
                            else root.st.connectWifi(nw.modelData.ssid, "");
                        }
                    }
                    RowLayout {
                        x: 9; y: 26; width: parent.width - 18; height: 22
                        spacing: 6
                        visible: netp.askFor === nw.modelData.ssid
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 20
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.08)
                            TextInput {
                                id: pass
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                font.family: Theme.font
                                font.pixelSize: 10
                                color: Theme.text
                                clip: true
                                onAccepted: { root.st.connectWifi(nw.modelData.ssid, text); netp.askFor = ""; netp.view = "map"; }
                                Keys.onEscapePressed: netp.askFor = ""
                                T { visible: pass.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Пароль (пусто — если сеть уже знакома)"; color: Theme.dim; font.pixelSize: 9 }
                            }
                        }
                        Btn { implicitHeight: 20; label: "Подключить"; on: true; onClicked: { root.st.connectWifi(nw.modelData.ssid, pass.text); netp.askFor = ""; netp.view = "map"; } }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }

        // ── Bluetooth ──
        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: tabs.top
            anchors.bottomMargin: 6
            visible: netp.tab === "bt"
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                G { text: root.st.btIcon; font.pixelSize: 18 }
                T { Layout.fillWidth: true; text: !root.st.bt ? "Bluetooth не найден" : root.st.btOn ? "Bluetooth включён" : "Bluetooth выключен"; font.weight: Font.Bold; font.pixelSize: 12 }
            }
            T { visible: root.st.btOn && root.st.btDevices.length === 0; text: "Нет сопряжённых устройств"; color: Theme.dim }
            Repeater {
                model: root.st.btOn ? root.st.btDevices.slice(0, 4) : []
                Rectangle {
                    id: dev
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: 8
                    color: dm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.cardSolid
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 7
                        G { text: dev.modelData.connected ? "󰂱" : "󰂯"; font.pixelSize: 12; color: dev.modelData.connected ? Theme.accent : Theme.sub }
                        T { Layout.fillWidth: true; text: dev.modelData.name || dev.modelData.address }
                        T { visible: dev.modelData.batteryAvailable; text: Math.round(dev.modelData.battery * 100) + "%"; color: Theme.dim }
                        T { text: dev.modelData.connected ? "откл." : "подкл."; color: Theme.dim; font.pixelSize: 9 }
                    }
                    MouseArea {
                        id: dm
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: dev.modelData.connected ? dev.modelData.disconnect() : dev.modelData.connect()
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }

        // tabs + power, as in the prototype
        Rectangle {
            id: tabs
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: tabRow.implicitWidth + 6
            height: 26
            radius: 9
            color: Theme.cardSolid
            Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: [{ id: "wifi", t: "Wi-Fi" }, { id: "bt", t: "Bluetooth" }]
                    Rectangle {
                        required property var modelData
                        width: tl.implicitWidth + 18; height: 20; radius: 7
                        color: netp.tab === modelData.id ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                        T { id: tl; anchors.centerIn: parent; text: parent.modelData.t; font.weight: Font.DemiBold; color: netp.tab === parent.modelData.id ? Theme.text : Theme.dim }
                        MouseArea { anchors.fill: parent; onClicked: netp.tab = parent.modelData.id }
                    }
                }
            }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 26; height: 26; radius: 13
            readonly property bool on: netp.tab === "wifi" ? root.st.wifiOn : root.st.btOn
            color: on ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
            G { anchors.centerIn: parent; text: "󰐥"; font.pixelSize: 13; color: parent.on ? Theme.accentInk : Theme.text }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (netp.tab === "wifi") root.st.setWifi(!root.st.wifiOn);
                    else if (root.st.bt) root.st.bt.enabled = !root.st.bt.enabled;
                }
            }
        }
    }

    // ── control centre under the avatar ──
    ColumnLayout {
        id: cc
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 4
        spacing: 7
        visible: root.which === "user"
        property bool power: false
        onVisibleChanged: power = false

        RowLayout {
            Layout.fillWidth: true
            spacing: 9
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: 17
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#7a3a3a" }
                    GradientStop { position: 0.5; color: "#3d5c8a" }
                    GradientStop { position: 1; color: "#5b7fb0" }
                }
                border.color: Qt.rgba(1, 1, 1, 0.25)
                clip: true
                T { anchors.centerIn: parent; text: root.st.user.charAt(0).toUpperCase(); font.pixelSize: 15; font.weight: Font.Bold; visible: root.st.face === "" }
                Image { anchors.fill: parent; anchors.margins: 1; visible: root.st.face !== ""; source: root.st.face !== "" ? "file://" + root.st.face : ""; sourceSize.width: 68; fillMode: Image.PreserveAspectCrop }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                T { text: root.st.user; font.pixelSize: 13; font.weight: Font.Bold }
                T { Layout.fillWidth: true; text: root.st.host + " · " + root.st.uptimeText; color: Theme.sub; font.pixelSize: 10 }
            }
            Btn { glyph: "󰅖"; implicitWidth: 24; implicitHeight: 24; onClicked: root.closeRequested() }
        }

        // sliders
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: sl.implicitHeight + 14
            radius: 12
            color: Theme.cardSolid
            ColumnLayout {
                id: sl
                anchors.fill: parent
                anchors.margins: 7
                anchors.leftMargin: 10
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    G { text: root.st.muted ? "󰖁" : "󰕾"; font.pixelSize: 12; color: Theme.sub; MouseArea { anchors.fill: parent; onClicked: root.st.toggleMute() } }
                    T { text: "Громкость"; Layout.preferredWidth: 58; color: Theme.sub }
                    Slider { Layout.fillWidth: true; value: root.st.muted ? 0 : root.st.volume; onMoved: v => root.st.setVolume(v) }
                    T { text: Math.round(root.st.volume * 100) + "%"; font.family: Theme.mono; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    G { text: "󰃠"; font.pixelSize: 12; color: Theme.sub }
                    T { text: "Яркость"; Layout.preferredWidth: 58; color: Theme.sub }
                    Slider { Layout.fillWidth: true; value: root.st.brightness; onMoved: v => root.st.setBrightness(v) }
                    T { text: Math.round(root.st.brightness * 100) + "%"; font.family: Theme.mono; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
                }
            }
        }

        // quick tiles
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "wifi", g: root.st.wifiIcon, t: "Wi-Fi", on: root.st.wifiOn },
                    { id: "bt", g: root.st.btIcon, t: "Bluetooth", on: root.st.btOn },
                    { id: "dnd", g: "󰂛", t: "Тишина", on: Config.data.dnd },
                    { id: "warm", g: "󰖨", t: "Тёплый", on: Config.data.warm }
                ]
                Rectangle {
                    id: qt
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: modelData.on ? Theme.accent : qm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.cardSolid
                    Behavior on color { ColorAnimation { duration: 180 } }
                    scale: qm.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        G { anchors.horizontalCenter: parent.horizontalCenter; text: qt.modelData.g; font.pixelSize: 15; color: qt.modelData.on ? Theme.accentInk : Theme.text }
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: qt.modelData.t; font.pixelSize: 9; color: qt.modelData.on ? Theme.accentInk : Theme.text }
                    }
                    MouseArea {
                        id: qm
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            let id = qt.modelData.id;
                            if (id === "wifi") root.st.setWifi(!root.st.wifiOn);
                            else if (id === "bt") { if (root.st.bt) root.st.bt.enabled = !root.st.bt.enabled; }
                            else if (id === "dnd") Config.data.dnd = !Config.data.dnd;
                            else Config.data.warm = !Config.data.warm;
                        }
                    }
                }
            }
        }

        // notifications
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Theme.cardSolid
            clip: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    T { Layout.fillWidth: true; text: "Уведомления"; font.pixelSize: 12; font.weight: Font.Bold }
                    Btn { visible: root.st.notifs.length > 0; label: "Очистить"; implicitHeight: 20; onClicked: root.st.clearNotifs() }
                }
                Repeater {
                    model: root.st.notifs.slice(0, 2)
                    RowLayout {
                        id: cn
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 7
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 22; implicitHeight: 22; radius: 7
                            color: Qt.rgba(1, 1, 1, 0.08)
                            G { anchors.centerIn: parent; text: "󰂚"; font.pixelSize: 11; color: Theme.sub }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            T { Layout.fillWidth: true; text: cn.modelData.summary || cn.modelData.appName; font.weight: Font.Bold }
                            T { Layout.fillWidth: true; visible: text !== ""; text: cn.modelData.body.replace(/\s+/g, " "); color: "#c9c9cf"; font.pixelSize: 10 }
                        }
                        MouseArea { Layout.preferredWidth: 0; Layout.preferredHeight: 0 }
                    }
                }
                Item {
                    visible: root.st.notifs.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        // little vinyl, as in the prototype's empty state
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 22; height: 22; radius: 11
                            color: "#0a0a0b"
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.sub }
                        }
                        T { text: "Всё прочитано"; color: Theme.dim }
                    }
                }
                Item { visible: root.st.notifs.length > 0; Layout.fillHeight: true }
            }
        }

        // bottom: temperature, wallpaper, settings, lock, power
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: !cc.power
            Rectangle {
                implicitWidth: tempRow.implicitWidth + 16; implicitHeight: 26; radius: 9
                color: Theme.cardSolid
                Row { id: tempRow; anchors.centerIn: parent; spacing: 4
                    G { text: "󰔏"; font.pixelSize: 11; color: Theme.sub }
                    T { text: Math.round(root.st.temp) + "°"; font.family: Theme.mono; font.weight: Font.Bold }
                }
            }
            Item { Layout.fillWidth: true }
            Btn { glyph: "󰸉"; onClicked: { Quickshell.execDetached(["quickshell", "ipc", "-p", Qt.resolvedUrl("shell.qml").toString().replace(/^file:\/\//, ""), "call", "ashen-settings", "open", "wall"]); root.closeRequested(); } }
            Btn { glyph: "󰒓"; onClicked: { Quickshell.execDetached(["quickshell", "ipc", "-p", Qt.resolvedUrl("shell.qml").toString().replace(/^file:\/\//, ""), "call", "ashen-settings", "open", ""]); root.closeRequested(); } }
            Btn { glyph: "󰌾"; onClicked: { Quickshell.execDetached(["quickshell", "ipc", "-p", Qt.resolvedUrl("shell.qml").toString().replace(/^file:\/\//, ""), "call", "ashen-lock", "lock"]); root.closeRequested(); } }
            Btn { glyph: "󰐥"; onClicked: cc.power = true }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: cc.power
            Btn { Layout.fillWidth: true; glyph: "󰐥"; label: "Выключить"; on: true; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
            Btn { Layout.fillWidth: true; glyph: "󰜉"; label: "Перезагрузить"; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
            Btn { glyph: "󰍃"; onClicked: Quickshell.execDetached(["swaymsg", "exit"]) }
            Btn { glyph: "󰅖"; onClicked: cc.power = false }
        }
    }

    // ── notifications ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 6
        spacing: 6
        visible: root.which === "notif"
        RowLayout {
            Layout.fillWidth: true
            T { text: "Уведомления"; font.pixelSize: 13; font.weight: Font.Bold; Layout.fillWidth: true }
            Btn { visible: root.st.notifs.length > 0; label: "Очистить"; implicitHeight: 22; onClicked: root.st.clearNotifs() }
        }
        T {
            visible: root.st.notifs.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 30
            horizontalAlignment: Text.AlignHCenter
            text: "Пока тихо"
            color: Theme.dim
            font.pixelSize: 12
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: root.st.notifs
            delegate: Rectangle {
                id: nItem
                required property var modelData
                width: ListView.view.width
                implicitHeight: nCol.implicitHeight + 12
                radius: 10
                color: nm.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Theme.cardSolid
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    anchors.leftMargin: 8
                    spacing: 8
                    Image {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        sourceSize.width: 20; sourceSize.height: 20
                        source: nItem.modelData.image || (nItem.modelData.appIcon ? Quickshell.iconPath(nItem.modelData.appIcon, true) : "")
                        visible: source != ""
                    }
                    ColumnLayout {
                        id: nCol
                        Layout.fillWidth: true
                        spacing: 1
                        T { Layout.fillWidth: true; text: nItem.modelData.summary || nItem.modelData.appName; font.weight: Font.Bold }
                        T {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: nItem.modelData.body
                            color: Theme.sub
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }
                        T { text: nItem.modelData.appName; color: Theme.dim; font.pixelSize: 9 }
                    }
                    G {
                        Layout.alignment: Qt.AlignTop
                        text: "󰅖"; font.pixelSize: 12; color: Theme.dim
                        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: nItem.modelData.dismiss() }
                    }
                }
                MouseArea {
                    id: nm
                    anchors.fill: parent
                    anchors.rightMargin: 24
                    hoverEnabled: true
                    onClicked: { root.st.activate(nItem.modelData); root.closeRequested(); }
                }
            }
        }
    }

    // ── weather ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        spacing: 8
        id: wxp
        visible: root.which === "wx"
        readonly property var w: root.st.weather
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            T { text: wxp.w ? Math.round(wxp.w.temp) + "°" : "—"; font.pixelSize: 34; font.weight: Font.Bold }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                T { Layout.fillWidth: true; text: wxp.w ? wxp.w.city : ""; font.weight: Font.Bold; font.pixelSize: 12 }
                T { Layout.fillWidth: true; text: root.st.weatherText; color: Theme.sub }
                T {
                    Layout.fillWidth: true
                    text: wxp.w ? "ощущается " + Math.round(wxp.w.feels) + "° · ветер " + Math.round(wxp.w.wind) + " м/с · " + wxp.w.humidity + "%" : ""
                    color: Theme.dim
                    font.pixelSize: 10
                }
            }
            G { text: wxp.w ? root.st.wmoGlyph(wxp.w.code, wxp.w.day) : ""; font.pixelSize: 30 }
        }
        // hourly bars
        RowLayout {
            id: hours
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            readonly property var hrs: wxp.w ? wxp.w.hours : []
            readonly property real lo: hrs.length ? Math.min.apply(null, hrs.map(h => h.temp)) : 0
            readonly property real hi: hrs.length ? Math.max.apply(null, hrs.map(h => h.temp)) : 1
            Repeater {
                model: hours.hrs
                ColumnLayout {
                    id: hr
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2
                    T { Layout.alignment: Qt.AlignHCenter; text: Math.round(hr.modelData.temp) + "°"; font.pixelSize: 9; font.weight: Font.Bold }
                    Item { Layout.fillHeight: true }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 12
                        implicitHeight: 6 + 24 * (hours.hi > hours.lo ? (hr.modelData.temp - hours.lo) / (hours.hi - hours.lo) : 0.5)
                        radius: 5
                        color: Theme.accent
                    }
                    T { Layout.alignment: Qt.AlignHCenter; text: hr.modelData.t.substring(0, 2); font.pixelSize: 9; color: Theme.dim }
                }
            }
        }
    }

    // ── app search ──
    ColumnLayout {
        id: finder
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 6
        spacing: 6
        visible: root.which === "find"

        readonly property var apps: {
            let q = query.text.trim().toLowerCase();
            let all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
            let hits = q === "" ? all : all.filter(a => (a.name + " " + (a.genericName || "") + " " + (a.keywords || []).join(" ")).toLowerCase().indexOf(q) >= 0);
            hits.sort((a, b) => a.name.localeCompare(b.name));
            return hits.slice(0, 5);
        }
        property int sel: 0
        onAppsChanged: sel = 0
        function launch(a) { if (!a) return; a.execute(); query.text = ""; root.closeRequested(); }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.07)
            border.color: Theme.line
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                spacing: 7
                G { text: ""; font.pixelSize: 12; color: Theme.sub }
                TextInput {
                    id: query
                    Layout.fillWidth: true
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentInk
                    clip: true
                    focus: root.active && root.which === "find"
                    onFocusChanged: if (focus) forceActiveFocus()
                    Keys.onEscapePressed: { text = ""; root.closeRequested(); }
                    Keys.onDownPressed: finder.sel = Math.min(finder.sel + 1, finder.apps.length - 1)
                    Keys.onUpPressed: finder.sel = Math.max(finder.sel - 1, 0)
                    onAccepted: finder.launch(finder.apps[finder.sel])
                    T { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Приложение…"; color: Theme.dim; visible: query.text === ""; font.pixelSize: 12 }
                }
            }
        }

        Repeater {
            model: finder.apps
            Rectangle {
                id: hit
                required property var modelData
                required property int index
                readonly property bool on: index === finder.sel
                Layout.fillWidth: true
                implicitHeight: 25
                radius: 8
                color: on ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8
                    Image {
                        source: Quickshell.iconPath(hit.modelData.icon, "application-x-executable")
                        sourceSize.width: 16
                        sourceSize.height: 16
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16
                    }
                    T { Layout.fillWidth: true; text: hit.modelData.name; font.pixelSize: 12; font.weight: hit.on ? Font.DemiBold : Font.Normal }
                    T { visible: hit.on; text: "↵"; color: Theme.dim }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: finder.sel = hit.index
                    onClicked: finder.launch(hit.modelData)
                }
            }
        }
    }
}
