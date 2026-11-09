import QtQuick
import QtQuick.Layouts

// Slides up over the composer when Claude Code asks to use a tool.
Rectangle {
    id: card
    property var request: null
    property string mode: ""
    signal answered(string decision)

    readonly property bool shown: request !== null
    radius: Theme.radius + 2
    color: Theme.card
    border.color: Qt.alpha(Theme.accent, 0.6)
    border.width: 1.5
    height: col.implicitHeight + 24

    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    transform: Translate { y: card.shown ? 0 : card.height + 20; Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1 } } }
    Behavior on opacity { NumberAnimation { duration: 220 } }

    // keep the last request visible while sliding out
    property var shownRequest: null
    onRequestChanged: if (request) shownRequest = request

    ColumnLayout {
        id: col
        x: 14; y: 12
        width: parent.width - 28
        spacing: 8

        RowLayout {
            spacing: 8
            Text { text: "󰒃"; font.family: Theme.font; font.pixelSize: 16; color: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: "Claude хочет использовать " + (card.shownRequest ? card.shownRequest.toolName : "")
                font.family: Theme.font
                font.pixelSize: 13
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
            }
        }

        Text {
            visible: text !== ""
            Layout.fillWidth: true
            text: card.shownRequest && card.shownRequest.summary !== card.shownRequest.detail ? card.shownRequest.summary : ""
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.sub
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: detail.implicitHeight + 12
            radius: 8
            color: Theme.bg
            visible: detail.text !== ""
            Text {
                id: detail
                x: 8; y: 6
                width: parent.width - 16
                text: card.shownRequest ? card.shownRequest.detail : ""
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.text
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PillButton {
                Layout.fillWidth: true
                label: "Разрешить"
                icon: "󰄬"
                primary: true
                onClicked: card.answered("allow")
            }
            PillButton {
                Layout.fillWidth: true
                label: "Всегда"
                icon: "󰁪"
                visible: card.shownRequest && card.shownRequest.suggestions && card.shownRequest.suggestions.length > 0
                onClicked: card.answered("always")
            }
            PillButton {
                Layout.fillWidth: true
                label: "Режим авто"
                icon: "󰚩"
                visible: card.mode !== "auto" && card.mode !== "plan"
                onClicked: card.answered("auto")
            }
            PillButton {
                Layout.fillWidth: true
                label: "Отклонить"
                icon: "󰜺"
                danger: true
                onClicked: card.answered("deny")
            }
        }
    }
}
