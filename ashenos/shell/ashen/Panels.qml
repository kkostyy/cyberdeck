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

    // ── calendar + clock ──
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 6
        spacing: 14
        visible: root.which === "clock"

        Rectangle {
            id: cal
            Layout.preferredWidth: 200
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            Item { Layout.fillHeight: true }
            T {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatTime(root.st.clock.date, "HH:mm:ss")
                font.family: Theme.mono
                font.pixelSize: 34
                font.weight: Font.Bold
            }
            T {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    let s = root.st.clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM");
                    return s.charAt(0).toUpperCase() + s.substring(1);
                }
                color: Theme.dim
                font.pixelSize: 12
            }
            Item { Layout.fillHeight: true }
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
            T { text: "Звук"; font.pixelSize: 13; font.weight: Font.Bold }
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

    // ── network ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        spacing: 8
        visible: root.which === "net"
        RowLayout {
            Layout.fillWidth: true
            G { text: root.st.wifiIcon; font.pixelSize: 20 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                T { Layout.fillWidth: true; text: !root.st.wifiOn ? "Wi-Fi выключен" : root.st.ssid || "Нет подключения"; font.pixelSize: 13; font.weight: Font.Bold }
                T { visible: root.st.ssid !== ""; text: "сигнал " + root.st.signal + "%"; color: Theme.dim }
            }
            Btn { glyph: "󰖩"; on: root.st.wifiOn; onClicked: root.st.setWifi(!root.st.wifiOn) }
        }
        Btn {
            Layout.fillWidth: true
            glyph: "󰒓"
            label: "Сети и пароли"
            onClicked: { Quickshell.execDetached(["kitty", "-e", "nmtui"]); root.closeRequested(); }
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

    // ── bluetooth ──
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        spacing: 6
        visible: root.which === "bt"
        RowLayout {
            Layout.fillWidth: true
            G { text: root.st.btIcon; font.pixelSize: 20 }
            T { Layout.fillWidth: true; text: "Bluetooth"; font.pixelSize: 13; font.weight: Font.Bold }
            Btn { glyph: "󰂯"; on: root.st.btOn; onClicked: if (root.st.bt) root.st.bt.enabled = !root.st.bt.enabled }
        }
        T {
            visible: root.st.btOn && root.st.btDevices.length === 0
            Layout.fillWidth: true
            text: "Нет сопряжённых устройств"
            color: Theme.dim
        }
        Repeater {
            model: root.st.btOn ? root.st.btDevices.slice(0, 3) : []
            Rectangle {
                id: dev
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 9
                color: dm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.cardSolid
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 7
                    G { text: dev.modelData.connected ? "󰂱" : "󰂯"; font.pixelSize: 12; color: dev.modelData.connected ? Theme.accent : Theme.sub }
                    T { Layout.fillWidth: true; text: dev.modelData.name || dev.modelData.address }
                    T { visible: dev.modelData.batteryAvailable; text: Math.round(dev.modelData.battery * 100) + "%"; color: Theme.dim }
                    T { text: dev.modelData.connected ? "откл." : "подкл."; color: Theme.dim; font.pixelSize: 10 }
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
