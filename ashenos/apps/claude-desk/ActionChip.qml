import QtQuick

// Small rounded action button under a reply (Заново / Продолжи / …).
Rectangle {
    id: chip
    property string icon: ""
    property string label: ""
    signal clicked()
    implicitWidth: chipRow.implicitWidth + 18
    implicitHeight: 28
    radius: 14
    color: chipMouse.pressed ? Theme.accent : chipMouse.containsMouse ? Theme.cardHi : Theme.card
    border.color: Theme.border
    Behavior on color { ColorAnimation { duration: 120 } }
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5
        Text { text: chip.icon; font.family: Theme.font; font.pixelSize: 13; color: chipMouse.pressed ? Theme.bg : Theme.accent }
        Text { text: chip.label; font.family: Theme.font; font.pixelSize: 12; color: chipMouse.pressed ? Theme.bg : Theme.sub }
    }
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}
