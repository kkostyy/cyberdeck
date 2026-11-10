import QtQuick

// Dark dotted screen behind the LED text (design board «Рабочий стол»).
Rectangle {
    radius: 10
    color: "#0e0e10"
    border.color: Qt.rgba(1, 1, 1, 0.05)
    clip: true
    Canvas {
        anchors.fill: parent
        onPaint: {
            let g = getContext("2d");
            g.fillStyle = "rgba(255,255,255,0.045)";
            for (let y = 1.5; y < height; y += 3) for (let x = 1.5; x < width; x += 3) g.fillRect(x, y, 1, 1);
        }
    }
}
