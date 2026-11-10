import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Session lock + idle: lock after 5 min, screen off after 7.5 min (not while music plays).
//   quickshell ipc call ashen-lock lock      — lock now
//   quickshell ipc call ashen-lock preview   — show the lock screen in a normal window
Scope {
    id: root
    required property var st
    property bool previewing: false

    WlSessionLock {
        id: sessionLock
        locked: false
        surface: Component {
            WlSessionLockSurface {
                color: Theme.bezel
                LockContent {
                    anchors.fill: parent
                    st: root.st
                    onUnlocked: sessionLock.locked = false
                }
            }
        }
    }

    LazyLoader {
        active: root.previewing
        FloatingWindow {
            title: "AshenOS — экран блокировки (превью)"
            implicitWidth: 695
            implicitHeight: 417
            color: Theme.bezel
            onClosed: root.previewing = false
            LockContent {
                anchors.fill: parent
                st: root.st
                preview: true
                onUnlocked: root.previewing = false
            }
        }
    }

    IdleMonitor {
        timeout: 300
        enabled: !root.st.playing && !sessionLock.locked
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) sessionLock.locked = true
    }
    IdleMonitor {
        timeout: 450
        enabled: !root.st.playing
        respectInhibitors: true
        onIsIdleChanged: Quickshell.execDetached(["swaymsg", "output * power " + (isIdle ? "off" : "on")])
    }

    IpcHandler {
        target: "ashen-lock"
        function lock(): void { sessionLock.locked = true; }
        function preview(): void { root.previewing = true; }
    }
}
