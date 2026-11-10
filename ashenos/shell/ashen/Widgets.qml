import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// Desktop widgets (design board «Рабочий стол»): LED clock + date card, weather and
// system side by side, music with the vinyl. Running lines use the dotted pixel font.
PanelWindow {
    id: w
    required property var modelData
    required property var st
    screen: modelData

    anchors { top: true; right: true }
    margins.top: Theme.barH + 6
    margins.right: Theme.side + 6
    implicitWidth: 264
    implicitHeight: col.implicitHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ashen-widgets"

    readonly property color paper: "#ececf0"
    readonly property color ink: "#111113"

    component T: Text {
        font.family: Theme.font
        color: w.ink
        elide: Text.ElideRight
    }
    component Card: Rectangle {
        default property alias content: inner.data
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 12
        radius: 16
        color: Theme.card
        border.color: Qt.rgba(1, 1, 1, 0.08)
        ColumnLayout { id: inner; anchors.fill: parent; anchors.margins: 6; spacing: 5 }
    }
    // "> A > B > C" running LED line
    component Marquee: LedScreen {
        id: mq
        property string text: ""
        implicitHeight: 20
        Row {
            id: mqRow
            y: (mq.height - height) / 2
            Repeater {
                model: 2
                DotText { text: mq.text; pixelSize: 11; pitch: 1.6 }
            }
            NumberAnimation on x {
                from: 0; to: -mqRow.width / 2
                duration: Math.max(6000, mqRow.width * 26)
                loops: Animation.Infinite
                running: w.visible
            }
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 6

        // ── clock ──
        Card {
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                LedScreen {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        DotText { text: Qt.formatTime(w.st.clock.date, "HH"); pixelSize: 22; pitch: 2.2 }
                        DotText {
                            text: ":"; pixelSize: 22; pitch: 2.2
                            opacity: w.st.clock.date.getSeconds() % 2 === 0 ? 1 : 0.15
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                        }
                        DotText { text: Qt.formatTime(w.st.clock.date, "mm"); pixelSize: 22; pitch: 2.2 }
                    }
                }
                Rectangle {
                    implicitWidth: 48; implicitHeight: 48; radius: 11
                    color: w.paper
                    Column {
                        anchors.centerIn: parent
                        spacing: -2
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: w.st.clock.date.toLocaleDateString(Qt.locale("ru_RU"), "ddd").toUpperCase(); font.pixelSize: 8; font.weight: Font.Bold }
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: w.st.clock.date.getDate(); font.pixelSize: 21; font.weight: Font.Bold }
                        T { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.locale("ru_RU").standaloneMonthName(w.st.clock.date.getMonth(), Locale.ShortFormat); font.pixelSize: 8 }
                    }
                }
            }
        }

        // ── weather + system ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Card {
                Layout.preferredWidth: 1
                Marquee {
                    Layout.fillWidth: true
                    text: w.st.weather ? "> " + w.st.weatherText.toUpperCase() + " > " + (w.st.weather.city || "").toUpperCase() + " > " + Math.round(w.st.weather.temp) + "° " : "> ПОГОДА > ЗАГРУЖАЮ "
                }
                Rectangle {
                    id: wxTile
                    Layout.fillWidth: true
                    implicitHeight: 92
                    radius: 11
                    color: w.paper
                    readonly property var wx: w.st.weather
                    readonly property var hrs: wx && wx.hours ? wx.hours : []
                    readonly property real lo: hrs.length ? Math.min.apply(null, hrs.map(h => h.temp)) : 0
                    readonly property real hi: hrs.length ? Math.max.apply(null, hrs.map(h => h.temp)) : 1
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            T { text: wxTile.wx ? Math.round(wxTile.wx.temp) + "°" : "—"; font.pixelSize: 26; font.weight: Font.DemiBold; font.letterSpacing: -1 }
                            Item { Layout.fillWidth: true }
                            Text { text: wxTile.wx ? w.st.wmoGlyph(wxTile.wx.code, wxTile.wx.day) : ""; font.family: Theme.icons; font.pixelSize: 18; color: w.ink; Layout.alignment: Qt.AlignTop }
                        }
                        T { text: wxTile.wx ? "ощущается как " + Math.round(wxTile.wx.feels) + "°" : ""; font.pixelSize: 7; font.weight: Font.DemiBold; opacity: 0.7 }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Repeater {
                                model: wxTile.hrs
                                ColumnLayout {
                                    id: hr
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 1
                                    T { Layout.alignment: Qt.AlignHCenter; text: Math.round(hr.modelData.temp) + "°"; font.pixelSize: 6; font.weight: Font.Bold }
                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 8
                                        implicitHeight: 4 + 14 * (wxTile.hi > wxTile.lo ? (hr.modelData.temp - wxTile.lo) / (wxTile.hi - wxTile.lo) : 0.5)
                                        radius: 3
                                        color: Qt.rgba(0.07, 0.07, 0.075, 0.78)
                                    }
                                    T { Layout.alignment: Qt.AlignHCenter; text: hr.modelData.t.substring(0, 2); font.pixelSize: 6; opacity: 0.6 }
                                }
                            }
                        }
                    }
                }
            }

            Card {
                Layout.preferredWidth: 1
                Marquee { Layout.fillWidth: true; text: "> СИСТЕМА > ASHENOS > RASPBERRY PI 4 " }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 92
                    radius: 11
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 0
                        Repeater {
                            model: [
                                { l: "ЦП", v: w.st.cpu, t: Math.round(w.st.cpu * 100) + "%" },
                                { l: "ОЗУ", v: w.st.ram, t: Math.round(w.st.ram * 100) + "%" },
                                { l: "Темп.", v: Math.min(1, w.st.temp / 85), t: Math.round(w.st.temp) + "°" }
                            ]
                            ColumnLayout {
                                id: mt
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2
                                Text { Layout.alignment: Qt.AlignHCenter; text: mt.modelData.t; font.family: Theme.font; font.pixelSize: 7; font.weight: Font.Bold; color: Theme.text }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillHeight: true
                                    implicitWidth: 18
                                    radius: 7
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: Math.max(width * 0.7, parent.height * mt.modelData.v)
                                        radius: 7
                                        color: w.paper
                                        Behavior on height { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                    }
                                }
                                Text { Layout.alignment: Qt.AlignHCenter; text: mt.modelData.l; font.family: Theme.font; font.pixelSize: 6; color: Theme.sub }
                            }
                        }
                    }
                }
            }
        }

        // ── music ──
        Card {
            Marquee {
                Layout.fillWidth: true
                text: w.st.player ? "> " + (w.st.trackTitle || "—").toUpperCase() + (w.st.trackArtist ? " > " + w.st.trackArtist.toUpperCase() : "") + " > " + w.st.user.toUpperCase() + " "
                                  : "> ТИШИНА > НИЧЕГО НЕ ИГРАЕТ "
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                // vinyl with metal balls rolling on it
                Rectangle {
                    implicitWidth: 86; implicitHeight: 86
                    radius: 11
                    color: "#121214"
                    border.color: Qt.rgba(1, 1, 1, 0.05)
                    Item {
                        id: disc
                        anchors.centerIn: parent
                        width: 72; height: 72
                        Rectangle { anchors.fill: parent; radius: width / 2; color: "#09090a"; border.color: "#1d1d20"; border.width: 3 }
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                anchors.centerIn: parent
                                width: 60 - index * 9; height: width; radius: width / 2
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.05)
                            }
                        }
                        Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: "#2a2a2e" }
                        RotationAnimation on rotation { from: 0; to: 360; duration: 5000; loops: Animation.Infinite; running: w.st.playing }
                        // chrome balls
                        Repeater {
                            model: [[0.40, 0.30, 11], [0.55, 0.42, 14], [0.33, 0.52, 13], [0.62, 0.62, 8], [0.45, 0.70, 7], [0.70, 0.36, 6]]
                            Shape {
                                required property var modelData
                                x: disc.width * modelData[0] - modelData[2] / 2
                                y: disc.height * modelData[1] - modelData[2] / 2
                                width: modelData[2]; height: modelData[2]
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeWidth: -1
                                    fillGradient: RadialGradient {
                                        centerX: width * 0.35; centerY: height * 0.3; centerRadius: width * 0.7
                                        focalX: width * 0.35; focalY: height * 0.3
                                        GradientStop { position: 0; color: "#ffffff" }
                                        GradientStop { position: 0.45; color: "#b9b9c0" }
                                        GradientStop { position: 1; color: "#3a3a40" }
                                    }
                                    PathAngleArc { centerX: width / 2; centerY: height / 2; radiusX: width / 2; radiusY: height / 2; startAngle: 0; sweepAngle: 360 }
                                }
                            }
                        }
                    }
                }
                // track tile
                Rectangle {
                    id: track
                    Layout.fillWidth: true
                    implicitHeight: 86
                    radius: 11
                    color: w.paper
                    readonly property var p: w.st.player
                    readonly property real pos: p ? p.position : 0
                    readonly property real len: p ? p.length : 0
                    function mmss(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 3
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Rectangle {
                                implicitWidth: 22; implicitHeight: 22; radius: 5
                                clip: true
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "#b8433f" }
                                    GradientStop { position: 0.5; color: "#e8e8f0" }
                                    GradientStop { position: 1; color: "#4f6fa8" }
                                }
                                Image { anchors.fill: parent; source: w.st.trackArt; sourceSize.width: 44; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -1
                                T { Layout.fillWidth: true; text: w.st.trackTitle || "Ничего не играет"; font.pixelSize: 10; font.weight: Font.Bold }
                                T { Layout.fillWidth: true; text: w.st.trackArtist || "~/Музыка"; font.pixelSize: 7; opacity: 0.6 }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8; radius: 4
                            color: "#cfcfd5"
                            Rectangle { width: track.len > 0 ? parent.width * track.pos / track.len : 0; height: parent.height; radius: 4; color: w.ink }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            T { text: track.mmss(track.pos); font.pixelSize: 19; font.weight: Font.Medium }
                            T { text: track.len > 0 ? track.mmss(track.len) : ""; font.pixelSize: 6; opacity: 0.6; Layout.alignment: Qt.AlignTop }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 24; implicitHeight: 24; radius: 12
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
