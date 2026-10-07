import QtQuick
import Quickshell
import Quickshell.Wayland

// Local AI full screen: an overlay over the whole screen, holding what Panel.qml hands it (its body, wide) and
// taking the keyboard while it is up. Panel.qml makes it when full screen opens and destroys it when it closes.
PanelWindow {
  property Component content
  visible: true
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-local-ai-full"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  Loader {
    id: body
    anchors.fill: parent
    sourceComponent: content
    onLoaded: Qt.callLater(function() { body.item.forceActiveFocus() })
  }
}
