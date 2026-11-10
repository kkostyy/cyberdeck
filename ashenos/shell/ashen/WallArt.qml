import QtQuick
import QtQuick.Shapes
import QtMultimedia

// AshenOS background art: near-black gradient, soft light arcs, waves at the bottom.
// Used by the wallpaper and the lock screen. `source` may be a picture or a video (live wallpaper).
Item {
    id: wall
    property string source: Config.data.wallpaper
    property string fill: Config.data.wallpaperFill
    property bool paused: false
    readonly property bool isVideo: /\.(mp4|webm|mkv|mov)$/i.test(source)
    readonly property int fillMode: fill === "fit" ? 1 : fill === "center" ? 2 : 0
    clip: true

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
            { y: 0.18, h: 1.15, o: 0.035, d: 46000 },
            { y: 0.34, h: 1.35, o: 0.025, d: 61000 }
        ]
        Rectangle {
            required property var modelData
            width: wall.width * 2.2
            height: wall.height * modelData.h
            radius: height / 2
            color: "transparent"
            border.width: wall.height * 0.035
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
    // soft waves behind the dock: two layers drifting at different speeds
    Repeater {
        model: [
            { amp: 16, base: 46, len: 1.0, o: 0.10, d: 24000 },
            { amp: 11, base: 30, len: 0.7, o: 0.16, d: 17000 }
        ]
        Item {
            id: wave
            required property var modelData
            anchors.bottom: parent.bottom
            width: wall.width * 2
            height: modelData.base + modelData.amp
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Qt.rgba(1, 1, 1, wave.modelData.o)
                    strokeWidth: -1
                    PathPolyline {
                        path: {
                            let pts = [], w = wave.width, h = wave.height, m = wave.modelData;
                            let period = wall.width * m.len;
                            for (let x = 0; x <= w; x += 8)
                                pts.push(Qt.point(x, h - m.base + m.amp * Math.sin(x / period * 2 * Math.PI)));
                            pts.push(Qt.point(w, h), Qt.point(0, h));
                            return pts;
                        }
                    }
                }
            }
            NumberAnimation on x {
                from: 0; to: -wall.width * wave.modelData.len
                duration: wave.modelData.d
                loops: Animation.Infinite
            }
        }
    }
    Image {
        anchors.fill: parent
        visible: wall.source !== "" && !wall.isVideo && status === Image.Ready
        source: wall.source !== "" && !wall.isVideo ? "file://" + wall.source : ""
        fillMode: [Image.PreserveAspectCrop, Image.PreserveAspectFit, Image.Pad][wall.fillMode]
        asynchronous: true
        sourceSize.width: wall.width
    }

    // live wallpaper: muted loop, paused while windows cover the desktop
    MediaPlayer {
        id: player
        source: wall.isVideo ? "file://" + wall.source : ""
        loops: MediaPlayer.Infinite
        videoOutput: video
        onSourceChanged: if (source != "" && !wall.paused) play()
        Component.onCompleted: if (source != "" && !wall.paused) play()
    }
    VideoOutput {
        id: video
        anchors.fill: parent
        visible: wall.isVideo
        fillMode: [VideoOutput.PreserveAspectCrop, VideoOutput.PreserveAspectFit, VideoOutput.PreserveAspectFit][wall.fillMode]
    }
    onPausedChanged: if (isVideo) { if (paused) player.pause(); else player.play(); }
}
