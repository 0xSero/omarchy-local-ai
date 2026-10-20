import QtQuick
import "View8.js" as View8

// Draws one page from View8.js: a header (where you came from, full screen and settings), cards of rows, and a foot
// with the page's actions. The same item draws the panel (340 wide) and full screen (wide); it runs nothing itself:
// every click is an action string handed to activated().
Item {
  id: page
  property var view: ({ cards: [] })
  property bool wide: false
  property string mono: "monospace"
  property color bg: "#161616"
  property color surface: "#1c1c1c"
  property color ink: "#ededed"
  property color valueTone: "#c4c4c4"
  property color labelTone: "#8c8c8c"
  property color ruleTone: "#2c2c2c"
  property color alertTone: "#f2a0a0"
  property string toggleGlyph: String.fromCodePoint(wide ? 0xf0294 : 0xf0293)
  property string gearGlyph: String.fromCodePoint(0xf0493)
  // the animation clock, ticking only while the page has something moving (the panel runs it)
  property int tick: 0
  readonly property bool drawn: tick >= 45
  signal activated(string action)

  readonly property int pad: wide ? 32 : 16
  readonly property int cardGap: wide ? 16 : 8
  readonly property int fontSize: wide ? 14 : 12
  readonly property real charW: metrics.averageCharacterWidth > 0 ? metrics.averageCharacterWidth : fontSize * 0.6
  FontMetrics { id: metrics; font.family: page.mono; font.pixelSize: page.fontSize }

  Rectangle { anchors.fill: parent; color: page.bg }

  // ---- header ----
  Item {
    id: head
    objectName: "local-ai-8-header"
    x: page.pad; y: page.wide ? 20 : 12
    width: page.width - 2 * page.pad
    height: 28
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: !!(page.view.header && page.view.header.left)
      text: page.view.header && page.view.header.left ? page.view.header.left.label : ""
      color: leftArea.containsMouse ? page.ink : page.labelTone
      font.family: page.mono; font.pixelSize: page.fontSize
      MouseArea { id: leftArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: page.activated(page.view.header.left.action) }
    }
    Text {
      anchors.centerIn: parent
      visible: page.wide
      text: page.view.header ? page.view.header.title || "" : ""
      color: page.labelTone
      font.family: page.mono; font.pixelSize: page.fontSize
    }
    Row {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      spacing: 16
      Text {
        objectName: "local-ai-8-toggle"
        text: page.toggleGlyph
        color: toggleArea.containsMouse ? page.ink : page.labelTone
        font.family: page.mono; font.pixelSize: page.fontSize + 4
        MouseArea { id: toggleArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: page.activated(page.view.header ? page.view.header.toggle : "full|on") }
      }
      Text {
        objectName: "local-ai-8-gear"
        visible: !!(page.view.header && page.view.header.gear)
        text: page.gearGlyph
        color: gearArea.containsMouse ? page.ink : page.labelTone
        font.family: page.mono; font.pixelSize: page.fontSize + 4
        MouseArea { id: gearArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: page.activated("page|settings") }
      }
    }
  }

  // ---- foot: the page's state line and its actions, always on screen ----
  Column {
    id: foot
    objectName: "local-ai-8-foot"
    x: page.pad
    width: page.width - 2 * page.pad
    anchors.bottom: parent.bottom; anchors.bottomMargin: page.wide ? 24 : 14
    spacing: 10
    visible: !!page.view.foot
    Text {
      width: parent.width
      visible: !!(page.view.foot && page.view.foot.note)
      text: page.view.foot ? page.view.foot.note || "" : ""
      color: page.view.foot && page.view.foot.alert ? page.alertTone : page.labelTone
      wrapMode: Text.WordWrap
      font.family: page.mono; font.pixelSize: page.fontSize
    }
    Row {
      spacing: 8
      visible: !!(page.view.foot && (page.view.foot.items || []).length)
      Repeater {
        model: page.view.foot ? page.view.foot.items || [] : []
        delegate: Btn { required property var modelData; item: modelData; big: true }
      }
    }
    Text {
      visible: !!(page.view.foot && page.view.foot.link)
      text: page.view.foot && page.view.foot.link ? page.view.foot.link.label : ""
      color: linkArea.containsMouse ? page.ink : page.labelTone
      font.family: page.mono; font.pixelSize: page.fontSize
      MouseArea { id: linkArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: page.activated(page.view.foot.link.action) }
    }
  }

  // ---- body: the cards, scrolling between header and foot ----
  Flickable {
    id: body
    objectName: "local-ai-8-body"
    x: page.pad
    y: head.y + head.height + (page.wide ? 18 : 12)
    width: page.width - 2 * page.pad
    height: (foot.visible ? foot.y - 14 : page.height - 14) - y
    contentHeight: cards.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: cards
      width: body.width
      spacing: page.cardGap
      Repeater {
        model: page.view.cards || []
        delegate: Rectangle {
          id: cardItem
          required property var modelData
          readonly property bool bare: !!modelData.bare
          width: cards.width
          height: bare && modelData.grow ? Math.max(inner.height, body.height) : inner.height + (bare ? 0 : 28)
          color: bare ? "transparent" : page.surface
          border.width: bare ? 0 : 1
          border.color: modelData.alert ? page.alertTone : page.ruleTone
          Column {
            id: inner
            x: cardItem.bare ? 0 : 16
            y: cardItem.bare ? (cardItem.modelData.grow ? Math.max(0, (body.height - height) / 2) : 0) : 14
            width: cardItem.width - 2 * x
            spacing: 8
            Repeater {
              model: cardItem.modelData.rows || []
              delegate: Loader {
                required property var modelData
                width: inner.width
                visible: !(modelData.untilDrawn && page.drawn) && !(modelData.afterDrawn && !page.drawn)
                sourceComponent: ({ hands: handsRow, title: titleRow, pre: preRow, note: noteRow, label: labelRow, figs: figsRow,
                  item: itemRow, kv: kvRow, block: blockRow, buttons: buttonsRow, links: linksRow, bars: barsRow, calendar: calendarRow })[modelData.type] || noteRow
                onLoaded: item.row = modelData
              }
            }
          }
        }
      }
    }
  }

  // ---- rows ----
  component Btn: Rectangle {
    id: btn
    property var item: ({})
    property bool big: false
    readonly property bool primary: !!item.primary
    readonly property bool live: !!item.action
    width: btnText.implicitWidth + (big ? 36 : 22)
    height: big ? 38 : 28
    color: primary ? page.ink : page.ruleTone
    opacity: live ? (btnArea.containsMouse ? 0.88 : 1) : 0.5
    Text { id: btnText; anchors.centerIn: parent; text: btn.item.label || ""; color: btn.primary ? page.bg : page.ink
      font.family: page.mono; font.pixelSize: page.fontSize; font.bold: btn.primary }
    MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; enabled: btn.live; cursorShape: Qt.PointingHandCursor
      onClicked: page.activated(btn.item.action) }
  }
  component Mono: Text {
    font.family: page.mono; font.pixelSize: page.fontSize
    color: page.valueTone
    textFormat: Text.PlainText
  }

  Component {
    id: handsRow
    Item {
      property var row: ({})
      height: art.implicitHeight * art.scale
      Text {
        id: art
        objectName: "local-ai-8-hands"
        text: View8.hands(page.tick)
        color: page.ink
        textFormat: Text.PlainText
        font.family: page.mono; font.pixelSize: 8
        lineHeightMode: Text.FixedHeight; lineHeight: 9
        transformOrigin: Item.TopLeft
        scale: implicitWidth > 0 ? Math.min(1, parent.width / implicitWidth) : 1
        x: (parent.width - implicitWidth * scale) / 2
      }
    }
  }
  Component {
    id: titleRow
    Item {
      property var row: ({})
      height: Math.max(titleCol.height, dots.height)
      Column {
        id: titleCol
        width: parent.width - dots.width - 12
        spacing: 6
        Mono { width: parent.width; text: parent.parent.row.text || ""; color: page.ink; font.pixelSize: page.wide ? 26 : 18; elide: Text.ElideRight }
        Mono { width: parent.width; text: parent.parent.row.sub || ""; color: page.labelTone; wrapMode: Text.WordWrap }
      }
      Text {
        id: dots
        objectName: "local-ai-8-strip"
        anchors.right: parent.right; anchors.bottom: parent.bottom
        readonly property var spec: parent.row.strip || null
        text: spec ? View8.strip(spec.kind, spec.frac, page.tick, spec.cols) : ""
        color: spec && spec.kind === "flat" ? page.labelTone : page.ink
        textFormat: Text.PlainText
        font.family: page.mono; font.pixelSize: page.wide ? 9 : 7
        lineHeightMode: Text.FixedHeight; lineHeight: page.wide ? 10 : 8
      }
    }
  }
  Component {
    id: preRow
    Mono {
      property var row: ({})
      text: row.text || ""
      color: page.ink
      lineHeight: row.spaced ? 1.15 : 1.0
      font.letterSpacing: row.spaced ? 1 : 0
      clip: true
    }
  }
  Component {
    id: noteRow
    Mono {
      property var row: ({})
      text: (row.spin ? "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[page.tick % 10] + " " : "") + (row.text || "")
      color: row.alert ? page.alertTone : page.labelTone
      wrapMode: Text.WordWrap
      horizontalAlignment: row.center ? Text.AlignHCenter : Text.AlignLeft
    }
  }
  Component {
    id: labelRow
    Item {
      property var row: ({})
      height: lbl.implicitHeight
      Mono { id: lbl; text: parent.row.text || ""; color: page.labelTone }
      Mono { anchors.right: parent.right; text: parent.row.right || ""; color: page.ink }
    }
  }
  Component {
    id: figsRow
    Grid {
      property var row: ({})
      columns: page.wide ? 4 : 2
      rowSpacing: 12
      Repeater {
        model: parent.row.cells || []
        delegate: Column {
          required property var modelData
          width: parent.width / parent.columns
          spacing: 4
          Mono { text: modelData.k; color: page.labelTone }
          Mono { text: modelData.v; color: page.ink }
        }
      }
    }
  }
  Component {
    id: itemRow
    Item {
      id: it
      property var row: ({})
      height: Math.max(name.implicitHeight, rowBtn.visible ? rowBtn.height : 0) + 6
      opacity: row.dim ? 0.5 : 1
      Row {
        id: lead
        anchors.verticalCenter: parent.verticalCenter
        Mono { text: it.row.prefix || ""; color: page.ruleTone === page.bg ? page.labelTone : Qt.lighter(page.ruleTone, 1.6) }
        Mono { visible: !!it.row.caret; text: (it.row.caret || "") + " "; color: page.labelTone }
      }
      Mono {
        id: name
        anchors.verticalCenter: parent.verticalCenter
        x: lead.width
        width: Math.max(0, right.x - x - 12)
        elide: Text.ElideRight
        text: (it.row.label || "") + (it.row.tag ? "  " + it.row.tag : "")
        color: it.row.quiet ? page.labelTone : it.row.node ? page.ink : itArea.containsMouse ? page.ink : page.valueTone
      }
      Row {
        id: right
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Item { visible: !!it.row.mid; anchors.verticalCenter: parent.verticalCenter; width: page.wide ? 130 : midText.implicitWidth; height: midText.implicitHeight
          Mono { id: midText; anchors.right: parent.right; text: it.row.mid || ""; color: page.labelTone } }
        Item { visible: !!it.row.right; anchors.verticalCenter: parent.verticalCenter; width: page.wide ? 96 : rightText.implicitWidth; height: rightText.implicitHeight
          Mono { id: rightText; anchors.right: parent.right; text: it.row.right || ""; color: page.labelTone } }
        Btn { id: rowBtn; visible: !!it.row.button; anchors.verticalCenter: parent.verticalCenter; item: it.row.button || {} }
      }
      MouseArea { id: itArea; anchors.fill: parent; anchors.rightMargin: rowBtn.visible ? rowBtn.width + 8 : 0; hoverEnabled: true
        enabled: !!it.row.action; cursorShape: Qt.PointingHandCursor; onClicked: page.activated(it.row.action) }
    }
  }
  Component {
    id: kvRow
    Item {
      id: kv
      property var row: ({})
      height: Math.max(val.implicitHeight, kvBtn.visible ? kvBtn.height : 0) + 10
      Mono { id: key; anchors.verticalCenter: parent.verticalCenter; width: page.wide ? 170 : 96; text: kv.row.label || ""; color: page.labelTone; elide: Text.ElideRight }
      Mono { id: val; anchors.verticalCenter: parent.verticalCenter; x: key.width + 8; width: Math.max(0, parent.width - x - (kvBtn.visible ? kvBtn.width + 12 : 0))
        text: kv.row.value || ""; color: page.ink; elide: Text.ElideRight }
      Btn { id: kvBtn; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: !!kv.row.button; item: kv.row.button || {} }
    }
  }
  Component {
    id: blockRow
    Column {
      id: bl
      property var row: ({})
      spacing: 10
      Item {
        width: bl.width; height: bName.implicitHeight
        Mono { id: bName; width: parent.width - bOn.width - 12; elide: Text.ElideRight; text: (bl.row.name || "") + (bl.row.tag ? "  " + bl.row.tag : ""); color: page.ink
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.activated(bl.row.action) } }
        Mono { id: bOn; anchors.right: parent.right; text: bl.row.on || ""; color: page.labelTone }
      }
      Item {
        width: bl.width; height: Math.max(bStrip.height, bBtns.height)
        Text { id: bStrip; anchors.verticalCenter: parent.verticalCenter; text: bl.row.strip ? View8.strip(bl.row.strip.kind, bl.row.strip.frac, page.tick, bl.row.strip.cols) : ""; color: bl.row.alert ? page.alertTone : page.ink
          textFormat: Text.PlainText; font.family: page.mono; font.pixelSize: page.wide ? 9 : 7; lineHeightMode: Text.FixedHeight; lineHeight: page.wide ? 10 : 8 }
        Mono { anchors.verticalCenter: parent.verticalCenter; x: bStrip.width + 14; width: Math.max(0, bBtns.x - x - 10); elide: Text.ElideRight
          text: bl.row.right || ""; color: bl.row.alert ? page.alertTone : page.ink }
        Row { id: bBtns; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
          Repeater { model: bl.row.items || []; delegate: Btn { required property var modelData; item: modelData } } }
      }
      Mono { visible: !!bl.row.error; width: bl.width; wrapMode: Text.WordWrap; text: bl.row.error || ""; color: page.alertTone }
    }
  }
  Component {
    id: buttonsRow
    Item {
      property var row: ({})
      height: bRow.height
      Row { id: bRow; spacing: 8; x: parent.row.center ? (parent.width - width) / 2 : 0
        Repeater { model: parent.parent.row.items || []; delegate: Btn { required property var modelData; item: modelData; big: true } } }
    }
  }
  // a bar chart, solid: one bar a step, scaled to the largest
  Component {
    id: barsRow
    Item {
      id: bars
      property var row: ({})
      readonly property var values: row.values || []
      height: row.height || 80
      Row {
        anchors.bottom: parent.bottom
        spacing: 2
        Repeater {
          model: bars.values
          delegate: Rectangle {
            required property var modelData
            width: Math.max(1, (bars.width - 2 * (bars.values.length - 1)) / Math.max(1, bars.values.length))
            height: Math.max(2, modelData * bars.height)
            anchors.bottom: parent.bottom
            color: page.ink
          }
        }
      }
    }
  }
  // the calendar of tokens: a square a day, a column a week, shaded in four steps
  Component {
    id: calendarRow
    Grid {
      id: cal
      property var row: ({})
      readonly property int weeks: row.weeks || 20
      readonly property real cell: Math.min(12, (width - 3 * (weeks - 1)) / weeks)
      rows: 7
      flow: Grid.TopToBottom
      spacing: 3
      Repeater {
        model: cal.row.cells || []
        delegate: Rectangle {
          required property var modelData
          width: cal.cell; height: cal.cell
          color: modelData > 0 ? page.ink : page.ruleTone
          opacity: modelData > 0 ? [0, 0.3, 0.5, 0.75, 1][modelData] : 1
        }
      }
    }
  }
  Component {
    id: linksRow
    Row {
      property var row: ({})
      spacing: 18
      Repeater {
        model: parent.row.items || []
        delegate: Mono {
          required property var modelData
          text: modelData.label
          color: modelData.action ? (lArea.containsMouse ? page.ink : page.valueTone) : page.labelTone
          MouseArea { id: lArea; anchors.fill: parent; hoverEnabled: true; enabled: !!modelData.action; cursorShape: Qt.PointingHandCursor
            onClicked: page.activated(modelData.action) }
        }
      }
    }
  }
}
