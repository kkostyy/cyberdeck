import QtQuick
import QtQuick.Shapes

// The black bezel: everything outside a rounded rectangle inset by the frame metrics.
Shape {
    id: shp
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
