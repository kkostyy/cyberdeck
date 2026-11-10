import QtQuick
import QtQuick.Effects

// LED-board text from the design: Press Start 2P seen through a grid of round dots
// (the prototype's mask: radial-gradient(circle, #000 1.15px, transparent 1.45px) / 3px 3px).
Item {
    id: dt
    property string text: ""
    property real pixelSize: 24
    property color color: "#ededf0"
    property real pitch: Math.max(2, pixelSize / 8)        // dot grid step
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label
        text: dt.text
        font.family: Theme.pixel
        font.pixelSize: dt.pixelSize
        color: dt.color
        visible: false
        layer.enabled: true
    }
    // white dots on transparent — the mask
    Canvas {
        id: dots
        width: label.width; height: label.height
        visible: false
        layer.enabled: true
        onPaint: {
            let g = getContext("2d");
            g.reset();
            g.fillStyle = "#ffffff";
            let p = dt.pitch, r = p * 0.42;
            for (let y = p / 2; y < height; y += p)
                for (let x = p / 2; x < width; x += p) { g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill(); }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
    MultiEffect {
        width: label.width; height: label.height
        source: label
        maskEnabled: true
        maskSource: dots
        maskThresholdMin: 0.4
        maskSpreadAtMin: 0.2
    }
}
