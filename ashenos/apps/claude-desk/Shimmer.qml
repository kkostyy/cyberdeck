import QtQuick

// Text with a highlight sweeping across it, like Claude Code's spinner line.
Row {
    id: shimmer
    property string text: ""
    property color baseColor: Theme.dim
    property color glowColor: Theme.accent
    property int pixelSize: 13
    property real phase: 0

    NumberAnimation on phase {
        from: -0.3; to: 1.3
        duration: 1600
        loops: Animation.Infinite
        running: shimmer.visible
    }

    Repeater {
        model: shimmer.text.length
        Text {
            readonly property real pos: shimmer.text.length > 1 ? index / (shimmer.text.length - 1) : 0
            readonly property real glow: Math.max(0, 1 - Math.abs(pos - shimmer.phase) * 5)
            text: shimmer.text[index]
            font.family: Theme.font
            font.pixelSize: shimmer.pixelSize
            color: Qt.tint(shimmer.baseColor, Qt.alpha(shimmer.glowColor, glow))
        }
    }
}
