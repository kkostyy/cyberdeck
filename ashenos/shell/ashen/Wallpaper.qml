import QtQuick
import Quickshell
import Quickshell.Wayland

// AshenOS background: near-black with soft light arcs, like the prototype.
// Set `image` to use a picture instead.
PanelWindow {
    id: wall
    property string image: ""
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "#0b0b0d"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "ashen-wallpaper"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: "#141417" }
            GradientStop { position: 0.55; color: "#0b0b0d" }
            GradientStop { position: 1; color: "#060607" }
        }
    }
    // two long glowing arcs drifting very slowly
    Repeater {
        model: [
            { y: 0.18, h: 1.15, o: 0.07, d: 46000 },
            { y: 0.34, h: 1.35, o: 0.045, d: 61000 }
        ]
        Rectangle {
            required property var modelData
            width: wall.width * 2.2
            height: wall.height * modelData.h
            radius: height / 2
            color: "transparent"
            border.width: wall.height * 0.05
            border.color: Qt.rgba(1, 1, 1, modelData.o)
            y: wall.height * modelData.y
            x: -wall.width * 0.4
            NumberAnimation on x {
                from: -wall.width * 0.55; to: -wall.width * 0.25
                duration: modelData.d; loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
        }
    }
    Image {
        anchors.fill: parent
        visible: wall.image !== ""
        source: wall.image
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
}
