import QtQuick

// Claude-style sunburst: rays pulse and the star spins while `active`.
Item {
    id: star
    property bool active: false
    property color color: Theme.accent
    property int rays: 12
    implicitWidth: 28
    implicitHeight: 28

    property real breathe: 0
    SequentialAnimation on breathe {
        running: star.active
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) star.breathe = 0
    }

    RotationAnimator on rotation {
        running: star.active
        from: star.rotation; to: star.rotation + 360
        duration: 2600
        loops: Animation.Infinite
    }

    Repeater {
        model: star.rays
        Rectangle {
            readonly property real len: star.height * (index % 2 === 0 ? 0.46 : 0.34) * (1 - 0.25 * star.breathe * ((index % 3) / 2))
            width: Math.max(2, star.width * 0.12)
            height: len
            radius: width / 2
            color: star.color
            x: star.width / 2 - width / 2
            y: star.height / 2 - height
            transform: Rotation { origin.x: width / 2; origin.y: height; angle: index * 360 / star.rays }
        }
    }
}
