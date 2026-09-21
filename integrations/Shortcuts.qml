import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sero.shortcuts"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: "Keyboard shortcuts · Ctrl + F1"
    onPressed: root.toggle()
  }
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: content
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    Flickable {
      anchors.fill: parent
      contentHeight: content.implicitHeight
      clip: true
      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)
        focus: true
        Keys.onEscapePressed: root.close()
        PanelHero { width: parent.width; title: "Keyboard shortcuts"; meta: "MAC → OMARCHY"; foreground: root.foreground; fontFamily: root.fontFamily }
        Text { width: parent.width; text: "Command works inside apps. Use Ctrl + Space, release, then a key for desktop actions."; wrapMode: Text.WordWrap; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        Repeater {
          model: [
            ["⌘ Space / ⌘ Tab", "Apps / next window"],
            ["⌃⌘ F", "Full screen"],
            ["⌘ W / ⌘ T", "Close / new tab¹"],
            ["⌘ D", "Bookmark / tiled terminal"],
            ["⌘ C / V / X", "Copy / paste / cut"],
            ["⌘ A / F / S", "Select all / find / save"],
            ["⌘ L / R", "Address bar / reload"],
            ["⌘ N / O / P", "New / open / print¹"],
            ["⌘ Z / ⇧⌘ Z", "Undo / redo"],
            ["Ctrl + F1", "This cheat sheet"],
            ["Ctrl + Space, then…", ""],
            ["K / A / I", "Help / Agents / Local AI"],
            ["Enter / B / Space", "Terminal / browser / menu"],
            ["1–9 / 0", "Workspace 1–10"],
            ["Shift + 1–9 / 0", "Move window to workspace"],
            ["Arrows / Shift + arrows", "Focus / swap window"],
            ["F / T / W", "Full screen / float / close"],
            ["Tab / P", "Next / previous window"],
            ["Esc", "Cancel shortcuts"]
          ]
          Item {
            required property var modelData
            width: parent.width
            implicitHeight: Math.max(shortcut.implicitHeight, description.implicitHeight) + Style.space(4)
            Text { id: shortcut; width: parent.width * 0.49; text: modelData[0]; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
            Text { id: description; anchors.right: parent.right; width: parent.width * 0.49; text: modelData[1]; horizontalAlignment: Text.AlignRight; color: Util.alpha(root.foreground, 0.65); font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }
        }
        Button { text: "Visual Mac controls guide"; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: { Quickshell.execDetached(["omarchy-launch-browser", Quickshell.env("HOME") + "/.local/share/omarchy/guides/macos-controls.html"]); root.close() } }
        Text { width: parent.width; text: "¹ In terminals: close / open a terminal window. Local AI: Ctrl + O sets the agent project folder. Tab switches provider. Esc goes back."; wrapMode: Text.WordWrap; color: Util.alpha(root.foreground, 0.65); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        Button { text: "All Omarchy keybindings"; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: { Quickshell.execDetached(["omarchy-menu-keybindings"]); root.close() } }
      }
    }
  }
}
