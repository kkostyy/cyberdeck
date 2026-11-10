import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop widgets in the right column (under windows): clock, system, music.
PanelWindow {
    id: w
    required property var modelData
    required property var st
    screen: modelData

    anchors { top: true; right: true }
    margins.top: Theme.barH + 8
    margins.right: Theme.side + 8
    implicitWidth: 232
    implicitHeight: col.implicitHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ashen-widgets"

    readonly property color paper: "#ececf0"
    readonly property color ink: "#0b0b0c"

    // ── system stats: cpu %, ram %, temperature °C ──
    property real cpu: 0
    property real ram: 0
    property real temp: 0
    property var _prev: null
    Process {
        id: sys
        command: ["bash", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.trim().split("\n");
                let c = l[0].trim().split(/\s+/).slice(1).map(Number);
                let idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0);
                if (w._prev) {
                    let dt = total - w._prev[1], di = idle - w._prev[0];
                    if (dt > 0) w.cpu = Math.max(0, Math.min(1, 1 - di / dt));
                }
                w._prev = [idle, total];
                let mt = parseInt(l[1].split(/\s+/)[1]), ma = parseInt(l[2].split(/\s+/)[1]);
                if (mt > 0) w.ram = 1 - ma / mt;
                w.temp = (parseInt(l[3]) || 0) / 1000;
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sys.running = true }

    // ── pieces ──
    component Card: Rectangle {
        default property alias content: inner.data
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 16
        radius: 16
        color: Theme.card
        border.color: Qt.rgba(1, 1, 1, 0.08)
        ColumnLayout { id: inner; anchors.fill: parent; anchors.margins: 8; spacing: 6 }
    }
    // dot-matrix screen
    component Matrix: Rectangle {
        radius: 10
        color: "#101012"
        border.color: Qt.rgba(1, 1, 1, 0.05)
        clip: true
        Canvas {
            anchors.fill: parent
            onPaint: {
                let g = getContext("2d");
                g.fillStyle = "rgba(255,255,255,0.05)";
                for (let y = 2; y < height; y += 3) for (let x = 2; x < width; x += 3) g.fillRect(x, y, 1, 1);
            }
        }
    }
    // "> A > B > C" running line
    component Marquee: Matrix {
        id: mq
        property string text: ""
        implicitHeight: 20
        Row {
            id: mqRow
            y: (mq.height - height) / 2
            spacing: 0
            Repeater {
                model: 2
                Text {
                    text: mq.text
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.letterSpacing: 0.5
                    color: "#bdbdc4"
                }
            }
            NumberAnimation on x {
                from: 0; to: -mqRow.width / 2
                duration: Math.max(6000, mqRow.width * 22)
                loops: Animation.Infinite
                running: w.visible
            }
        }
    }
    component Bar_: ColumnLayout {
        property real value: 0
        property string label: ""
        property string valueText: ""
        spacing: 3
        Text { Layout.alignment: Qt.AlignHCenter; text: parent.valueText; font.family: Theme.font; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.text }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 24
            implicitHeight: 52
            radius: 7
            color: Qt.rgba(1, 1, 1, 0.08)
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.max(width * 0.6, parent.height * parent.parent.value)
                radius: 7
                color: w.paper
                Behavior on height { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
            }
        }
        Text { Layout.alignment: Qt.AlignHCenter; text: parent.label; font.family: Theme.font; font.pixelSize: 8; color: Theme.sub }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 8

        // clock
        Card {
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Matrix {
                    Layout.fillWidth: true
                    implicitHeight: 50
                    Text {
                        anchors.centerIn: parent
                        text: Qt.formatTime(w.st.clock.date, "HH:mm")
                        font.family: Theme.mono
                        font.pixelSize: 24
                        font.letterSpacing: 2
                        color: "#d4d4da"
                    }
                }
                Rectangle {
                    implicitWidth: 50
                    implicitHeight: 50
                    radius: 10
                    color: w.paper
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: -2
                        Text { Layout.alignment: Qt.AlignHCenter; text: w.st.clock.date.toLocaleDateString(Qt.locale("ru_RU"), "ddd").toUpperCase(); font.family: Theme.font; font.pixelSize: 8; font.weight: Font.Bold; color: w.ink }
                        Text { Layout.alignment: Qt.AlignHCenter; text: w.st.clock.date.getDate(); font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold; color: w.ink }
                        Text { Layout.alignment: Qt.AlignHCenter; text: Qt.locale("ru_RU").standaloneMonthName(w.st.clock.date.getMonth(), Locale.ShortFormat); font.family: Theme.font; font.pixelSize: 8; color: w.ink }
                    }
                }
            }
        }

        // system
        Card {
            Marquee { Layout.fillWidth: true; text: "> ASHENOS > ARCH LINUX ARM > RASPBERRY PI 4 > SWAY > QUICKSHELL "; }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Bar_ { value: w.cpu; label: "ЦП"; valueText: Math.round(w.cpu * 100) + "%" }
                Item { Layout.fillWidth: true }
                Bar_ { value: w.ram; label: "ОЗУ"; valueText: Math.round(w.ram * 100) + "%" }
                Item { Layout.fillWidth: true }
                Bar_ { value: Math.min(1, w.temp / 85); label: "Темп."; valueText: Math.round(w.temp) + "°" }
            }
        }

        // music
        Card {
            Marquee {
                Layout.fillWidth: true
                text: w.st.player ? "> " + (w.st.trackTitle || "—").toUpperCase() + (w.st.trackArtist ? " > " + w.st.trackArtist.toUpperCase() : "") + " "
                                  : "> ТИШИНА > НИЧЕГО НЕ ИГРАЕТ "
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                // vinyl
                Rectangle {
                    implicitWidth: 74; implicitHeight: 74
                    radius: 12
                    color: "#121214"
                    Rectangle {
                        id: disc
                        anchors.centerIn: parent
                        width: 64; height: 64; radius: 32
                        color: "#0a0a0b"
                        border.color: "#1d1d20"
                        border.width: 3
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                anchors.centerIn: parent
                                width: 52 - index * 10; height: width; radius: width / 2
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.05)
                            }
                        }
                        Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 8; color: w.paper }
                        Rectangle { x: 14; y: 10; width: 8; height: 3; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.18); rotation: -40 }
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 4000
                            loops: Animation.Infinite
                            running: w.st.playing
                        }
                    }
                }
                // track card
                Rectangle {
                    id: track
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: 12
                    color: w.paper
                    readonly property var p: w.st.player
                    readonly property real pos: p ? p.position : 0
                    readonly property real len: p ? p.length : 0
                    function mmss(s) { s = Math.max(0, Math.floor(s)); return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0"); }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 3
                        Text { Layout.fillWidth: true; text: w.st.trackTitle || "Ничего не играет"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold; color: w.ink; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; visible: text !== ""; text: w.st.trackArtist; font.family: Theme.font; font.pixelSize: 9; color: "#55555c"; elide: Text.ElideRight }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: 3
                            color: "#cfcfd5"
                            Rectangle {
                                width: track.len > 0 ? parent.width * track.pos / track.len : 0
                                height: parent.height; radius: 3; color: w.ink
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: track.mmss(track.pos); font.family: Theme.font; font.pixelSize: 16; color: w.ink }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 22; implicitHeight: 22; radius: 11
                                color: w.ink
                                scale: pm.pressed ? 0.85 : 1
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Text { anchors.centerIn: parent; text: w.st.playing ? "󰏤" : "󰐊"; font.family: Theme.icons; font.pixelSize: 11; color: w.paper }
                                MouseArea { id: pm; anchors.fill: parent; onClicked: if (w.st.player) w.st.player.togglePlaying() }
                            }
                        }
                    }
                }
            }
        }
    }
}
