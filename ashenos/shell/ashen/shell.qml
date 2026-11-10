//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// AshenOS shell: black bezel frame, top bar with the island, and liquid drops.
ShellRoot {
    id: root
    Status { id: status }
    Lock { st: status }

    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property var modelData
            Wallpaper { screen: perScreen.modelData }
            Widgets { modelData: perScreen.modelData; st: status }
            Frame { screen: perScreen.modelData }
            Bar { modelData: perScreen.modelData; st: status }
            Dock { modelData: perScreen.modelData }
        }
    }

    IpcHandler {
        target: "ashen-shell"
        function reload(): void { Quickshell.reload(false); }
    }
}
