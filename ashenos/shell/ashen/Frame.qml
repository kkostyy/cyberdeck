import QtQuick
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

        Bezel { anchors.fill: parent }
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
