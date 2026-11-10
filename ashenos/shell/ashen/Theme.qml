pragma Singleton
import QtQuick
import Quickshell

// AshenOS palette and metrics (from design/prototype, scaled for the 800×480 deck screen).
Singleton {
    readonly property color bezel: "#050506"
    readonly property color card: Qt.rgba(20 / 255, 20 / 255, 23 / 255, 0.74)
    readonly property color cardSolid: "#141417"
    readonly property color hover: Qt.rgba(1, 1, 1, 0.12)
    readonly property color line: Qt.rgba(1, 1, 1, 0.06)
    readonly property color text: "#e8e8ec"
    readonly property color sub: "#a1a1a8"
    readonly property color dim: "#8b8b93"
    readonly property color accent: "#f2f2f4"
    readonly property color accentInk: "#0b0b0c"

    readonly property string font: "Inter"
    readonly property string mono: "JetBrains Mono"
    readonly property string icons: "Iosevka Nerd Font"
    readonly property string pixel: "Press Start 2P"        // LED-board text (fonts/, OFL)

    // frame
    readonly property int barH: 30
    readonly property int side: 6
    readonly property int radius: 14

    // liquid drop: strip (hover) and panel (click)
    readonly property int stripH: 26
    readonly property int stripSide: 34
    readonly property int panelSide: 26

    // easing from the prototype
    readonly property var easeOut: [0.22, 1, 0.36, 1, 1, 1]
    readonly property var easeSlide: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var easeIn: [0.65, 0, 0.35, 1, 1, 1]
}
