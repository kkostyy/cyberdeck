import QtQuick
import QtQuick.Layouts

// Rounded button with a press "squish"; `primary` fills it with the accent colour.
Rectangle {
    id: btn
    property string label: ""
    property string icon: ""
    property bool primary: false
    property bool danger: false
    property bool active: false
    property int pixelSize: 12
    signal clicked()

    implicitHeight: 34
    implicitWidth: label === "" ? implicitHeight : row.implicitWidth + 24
    radius: height / 2

    readonly property color fg: primary ? Theme.bg : danger ? Theme.error : active ? Theme.bg : Theme.text
    color: primary ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
         : active ? Theme.accent
         : mouse.containsMouse ? Theme.cardHi : Qt.alpha(Theme.cardHi, 0.6)
    border.color: danger ? Qt.alpha(Theme.error, 0.45) : "transparent"
    Behavior on color { ColorAnimation { duration: 160 } }

    scale: mouse.pressed ? 0.94 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 3 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: btn.icon !== ""
            text: btn.icon
            font.family: Theme.font
            font.pixelSize: btn.pixelSize + 2
            color: btn.fg
        }
        Text {
            visible: btn.label !== ""
            text: btn.label
            font.family: Theme.font
            font.pixelSize: btn.pixelSize
            font.bold: true
            color: btn.fg
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
