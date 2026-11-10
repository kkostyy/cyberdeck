import QtQuick
import QtQuick.Layouts

// One-line hover strips under the bezel.
Item {
    id: root
    property string which: ""
    required property var st

    component T: Text {
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.text
        elide: Text.ElideRight
    }
    component G: Text {
        font.family: Theme.icons
        font.pixelSize: 12
        color: Theme.sub
    }

    RowLayout {
        anchors.fill: parent
        anchors.bottomMargin: 2
        spacing: 7
        visible: root.which === "clock"
        G { text: "󰃭" }
        T {
            Layout.fillWidth: true
            text: root.st.clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM")
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.bottomMargin: 2
        spacing: 8
        visible: root.which === "vol"
        G { text: root.st.muted ? "󰖁" : "󰕾" }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.14)
            Rectangle {
                width: parent.width * (root.st.muted ? 0 : root.st.volume)
                height: parent.height
                radius: 2
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }
        T { text: Math.round(root.st.volume * 100) + "%"; font.family: Theme.mono }
    }

    RowLayout {
        anchors.fill: parent
        anchors.bottomMargin: 2
        spacing: 6
        visible: root.which === "music"
        Repeater {
            model: [
                { g: "󰒮", f: () => root.st.player && root.st.player.previous() },
                { g: root.st.playing ? "󰏤" : "󰐊", f: () => root.st.player && root.st.player.togglePlaying() },
                { g: "󰒭", f: () => root.st.player && root.st.player.next() }
            ]
            G {
                required property var modelData
                text: modelData.g
                color: index === 1 ? Theme.accent : Theme.dim
                required property int index
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: parent.modelData.f() }
            }
        }
        T {
            Layout.fillWidth: true
            text: root.st.trackTitle + (root.st.trackArtist ? "  ·  " + root.st.trackArtist : "")
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.bottomMargin: 2
        spacing: 7
        visible: root.which === "net"
        G { text: root.st.wifiIcon }
        T {
            Layout.fillWidth: true
            text: !root.st.wifiOn ? "Wi-Fi выключен" : root.st.ssid === "" ? "Нет подключения" : root.st.ssid
        }
        T { visible: root.st.ssid !== ""; text: root.st.signal + "%"; color: Theme.dim; font.family: Theme.mono }
    }
}
