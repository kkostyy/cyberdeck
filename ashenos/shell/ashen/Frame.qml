import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// The black bezel around the screen: thin sides and bottom, rounded inner corners.
// Purely visual (clicks pass through); the bar provides the thick top edge.
Scope {
    id: frame
    required property var screen

    PanelWindow {
        screen: frame.screen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "ashen-frame"
        mask: Region {}

        Shape {
            id: shp
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.bezel
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                // outer rectangle
                startX: 0; startY: 0
                PathLine { x: shp.width; y: 0 }
                PathLine { x: shp.width; y: shp.height }
                PathLine { x: 0; y: shp.height }
                PathLine { x: 0; y: 0 }
                // inner rounded hole
                PathMove { x: Theme.side + Theme.radius; y: Theme.barH }
                PathLine { x: shp.width - Theme.side - Theme.radius; y: Theme.barH }
                PathArc { x: shp.width - Theme.side; y: Theme.barH + Theme.radius; radiusX: Theme.radius; radiusY: Theme.radius }
                PathLine { x: shp.width - Theme.side; y: shp.height - Theme.side - Theme.radius }
                PathArc { x: shp.width - Theme.side - Theme.radius; y: shp.height - Theme.side; radiusX: Theme.radius; radiusY: Theme.radius }
                PathLine { x: Theme.side + Theme.radius; y: shp.height - Theme.side }
                PathArc { x: Theme.side; y: shp.height - Theme.side - Theme.radius; radiusX: Theme.radius; radiusY: Theme.radius }
                PathLine { x: Theme.side; y: Theme.barH + Theme.radius }
                PathArc { x: Theme.side + Theme.radius; y: Theme.barH; radiusX: Theme.radius; radiusY: Theme.radius }
            }
        }
    }

    // reserve the thin edges so windows sit inside the bezel
    component Edge: PanelWindow {
        screen: frame.screen
        color: "transparent"
        exclusiveZone: Theme.side
        implicitWidth: Theme.side
        implicitHeight: Theme.side
        mask: Region {}
        WlrLayershell.namespace: "ashen-edge"
    }
    Edge { anchors { left: true; top: true; bottom: true } }
    Edge { anchors { right: true; top: true; bottom: true } }
    Edge { anchors { bottom: true; left: true; right: true } }
}
