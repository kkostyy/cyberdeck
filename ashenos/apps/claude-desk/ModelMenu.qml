import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Model + effort picker; lists what the CLI reported in its initialize response.
Popup {
    id: pop
    required property var ses

    padding: 8
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property var effortLabels: ({ "": "авто", low: "низкий", medium: "средний", high: "высокий", xhigh: "оч. высокий", max: "максимум" })
    readonly property var effortLevels: {
        let info = pop.ses.currentModelInfo;
        return [""].concat(info && info.supportedEffortLevels ? info.supportedEffortLevels : []);
    }

    background: Rectangle {
        radius: Theme.radius + 2
        color: Theme.card
        border.color: Theme.border
        border.width: 1
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
        NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 120 } }

    component Caption: Text {
        Layout.leftMargin: 8
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.dim
    }

    contentItem: ColumnLayout {
        spacing: 4

        // effort first: it stays visible however long the model list gets
        Caption {
            visible: pop.effortLevels.length > 1
            text: pop.ses.busy ? "Глубина размышлений (после ответа)" : "Глубина размышлений"
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.preferredWidth: 330
            spacing: 6
            visible: pop.effortLevels.length > 1
            Repeater {
                model: pop.effortLevels
                PillButton {
                    required property var modelData
                    implicitHeight: 28
                    label: pop.effortLabels[modelData] || modelData
                    active: pop.ses.effort === modelData
                    opacity: pop.ses.busy ? 0.5 : 1
                    onClicked: if (!pop.ses.busy) pop.ses.setEffort(modelData)
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: 1
            color: Theme.border
            visible: pop.effortLevels.length > 1
        }

        Caption { text: "Модель" }
        Caption {
            visible: pop.ses.models.length === 0
            text: "Список появится, когда Claude Code запустится"
            font.pixelSize: 12
            color: Theme.sub
        }

        Flickable {
            id: modelList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: modelCol.implicitHeight
            Layout.preferredWidth: modelCol.implicitWidth
            contentHeight: modelCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
            }

            ColumnLayout {
                id: modelCol
                width: modelList.width
                spacing: 2

                Repeater {
                    model: pop.ses.models
                    Rectangle {
                        id: mRow
                        required property var modelData
                        readonly property bool current: (pop.ses.modelChoice === "" ? "default" : pop.ses.modelChoice) === modelData.value
                        Layout.fillWidth: true
                        implicitWidth: mRowLayout.implicitWidth + 20
                        implicitHeight: 40
                        radius: Theme.radius - 2
                        color: mMouse.containsMouse ? Theme.cardHi : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            id: mRowLayout
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: mRow.modelData.displayName
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: mRow.current ? Theme.accent : Theme.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: mRow.modelData.description || ""
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    color: Theme.sub
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                text: mRow.current ? "󰄬" : ""
                                font.family: Theme.font
                                font.pixelSize: 15
                                color: Theme.accent
                            }
                        }
                        MouseArea {
                            id: mMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pop.ses.setModel(mRow.modelData.value === "default" ? "" : mRow.modelData.value);
                                pop.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
