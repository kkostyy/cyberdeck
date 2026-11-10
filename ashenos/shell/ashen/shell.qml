//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// AshenOS shell: black bezel frame, top bar with the island, and liquid drops.
ShellRoot {
    id: root
    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property var modelData
            Wallpaper { screen: perScreen.modelData }
            Frame { screen: perScreen.modelData }
            Bar { modelData: perScreen.modelData; id: bar }
        }
    }

    IpcHandler {
        target: "ashen-shell"
        function reload(): void { Quickshell.reload(false); }
    }
}
