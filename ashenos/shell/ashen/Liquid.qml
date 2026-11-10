import QtQuick
import QtQuick.Shapes

// The AshenOS "drop": black shape flowing out of the bezel.
// t = 0 — hover strip: long soft S-curves down to a flat bottom;
// t = 1 — panel: liquid fillet only near the bezel, then straight sides and rounded bottom.
// Same path commands in both states, so every value animates smoothly (as in the prototype).
Shape {
    id: s
    property real t: 0
    property color fill: Theme.bezel

    readonly property real w: width
    readonly property real h: height
    readonly property real cs: Math.min(Theme.stripSide, w / 2)
    readonly property real cb: Math.min(Theme.panelSide, w / 2)
    readonly property real kb: Math.min(h, 30)
    readonly property real c: cs + (cb - cs) * t
    readonly property real k: h + (kb - h) * t
    readonly property real r: Math.min(14, Math.max(0, h - kb)) * t
    readonly property real a1: c * (0.5 + 0.12 * t)
    readonly property real a2: c * (0.5 + 0.5 * t)
    readonly property real b2: h + (k * 0.38 - h) * t

    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        fillColor: s.fill
        strokeWidth: -1
        startX: 0; startY: 0
        PathCubic { control1X: s.a1; control1Y: 0; control2X: s.a2; control2Y: s.b2; x: s.c; y: s.k }
        PathLine { x: s.c; y: s.h - s.r }
        PathQuad { controlX: s.c; controlY: s.h; x: s.c + s.r; y: s.h }
        PathLine { x: s.w - s.c - s.r; y: s.h }
        PathQuad { controlX: s.w - s.c; controlY: s.h; x: s.w - s.c; y: s.h - s.r }
        PathLine { x: s.w - s.c; y: s.k }
        PathCubic { control1X: s.w - s.a2; control1Y: s.b2; control2X: s.w - s.a1; control2Y: 0; x: s.w; y: 0 }
        PathLine { x: 0; y: 0 }
    }
}
