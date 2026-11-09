import QtQuick

// Small animated on/off switch.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.accent : Qt.alpha(Theme.cardHi, mouse.containsMouse ? 1 : 0.8)
    border.color: checked ? "transparent" : Theme.border
    Behavior on color { ColorAnimation { duration: 160 } }

    Rectangle {
        width: sw.height - 6
        height: width
        radius: width / 2
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        color: sw.checked ? Theme.bg : Theme.sub
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
