import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Slash-command / skill picker that floats above the composer.
Rectangle {
    id: menu
    property var items: []
    property bool open: false
    property int current: 0
    signal picked(var cmd)

    readonly property bool shown: open && items.length > 0
    readonly property int rowH: 40
    onItemsChanged: current = 0

    function move(d) {
        if (items.length === 0) return;
        current = (current + d + items.length) % items.length;
        list.positionViewAtIndex(current, ListView.Contain);
    }
    function pickCurrent() { if (shown) picked(items[current]); }

    radius: Theme.radius + 2
    color: Theme.card
    border.color: Theme.border
    border.width: 1
    height: Math.min(items.length, 6) * rowH + 12

    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 160 } }
    transform: Translate { y: menu.shown ? 0 : 12; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        model: menu.items
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
        }

        delegate: Rectangle {
            id: rowItem
            required property var modelData
            required property int index
            width: list.width
            height: menu.rowH
            radius: Theme.radius - 2
            color: index === menu.current ? Theme.cardHi : rowMouse.containsMouse ? Qt.alpha(Theme.cardHi, 0.5) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }

            readonly property bool isSkill: modelData.name.indexOf(":") >= 0 || (modelData.description || "").startsWith("(")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: rowItem.isSkill ? "󰘦" : "󰘳"
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: index === menu.current ? Theme.accent : Theme.dim
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "/" + modelData.name
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.text
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: (modelData.argumentHint || "") !== ""
                            text: modelData.argumentHint || ""
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (modelData.description || "").replace(/^\([^)]*\)\s*/, "")
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.sub
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: menu.current = index
                onClicked: menu.picked(modelData)
            }
        }
    }
}
