import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Icons.js" as Icons
import "GearHeart.js" as GearHeart

// One card per connected monitor, holding the workspaces that live on it.
// Drag a workspace onto another card to move it there (now, and from then on);
// click one to make it the workspace that monitor shows when it connects.
// Everything that touches Hyprland or a file goes through bin/workspace-monitors.
Panel {
  id: root
  moduleName: "drorko.workspace-monitors"
  // `omarchy-shell shell toggle drorko.workspace-monitors` reaches the panel
  // through the shell, so no per-bar IpcHandler (two bars would mean two).
  manageIpc: false

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("bin/workspace-monitors").toString().replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // The bar font has no U+2605; this is Nerd Font's star.
  readonly property string starGlyph: "\uF005"
  // Extra glyph rules from this widget's shell.json entry, searched first.
  readonly property var userIconRules: Icons.compile(root.setting("iconRules", []))
  readonly property var heartShape: GearHeart.build(18, 2.6, 0.5)

  property var model: ({ monitors: [], workspaces: [], windows: [], rules: {} })
  property bool refreshQueued: false

  // Drag state lives here, not on the chip: the chip being dragged stays in
  // its card while a ghost follows the pointer across the whole panel.
  property int dragWs: -1
  property point dragPoint: Qt.point(0, 0)
  property string dropTarget: ""

  readonly property var monitors: model.monitors || []
  readonly property var externals: monitors.filter(function(m) { return !m.laptop })

  function monitorTitle(m) {
    if (m.laptop) return "Laptop"
    return root.externals.length > 1 ? "External " + (root.externals.indexOf(m) + 1) : "External"
  }

  function monitorByName(name) {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].name === name) return monitors[i]
    return null
  }

  function monitorByKey(key) {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].key === key || monitors[i].name === key) return monitors[i]
    return null
  }

  function fallbackMonitor() {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].laptop) return monitors[i]
    return monitors.length > 0 ? monitors[0] : null
  }

  function liveWorkspace(id) {
    var list = model.workspaces || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  function rule(id) {
    var r = model.rules ? model.rules[String(id)] : undefined
    return r || null
  }

  // Same set the bar shows: 1-5 always, 6-10 while they exist.
  readonly property var workspaceIds: {
    var ids = [1, 2, 3, 4, 5]
    var list = model.workspaces || []
    for (var i = 0; i < list.length; i++) {
      var id = list[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    return ids.sort(function(a, b) { return a - b })
  }

  // Where a workspace is shown: where it lives if it exists, else where its
  // rule will put it, else where Hyprland would create it.
  function homeOf(id) {
    var live = liveWorkspace(id)
    if (live) return live.monitor
    var r = rule(id)
    var m = r ? monitorByKey(r.monitor) : null
    if (m) return m.name
    var f = fallbackMonitor()
    return f ? f.name : ""
  }

  // A rule pointing at a monitor that is not connected: the workspace is
  // borrowing this screen and goes back when that one returns.
  function awayFromHome(id) {
    var r = rule(id)
    return r !== null && monitorByKey(r.monitor) === null
  }

  function isDefault(id, monitorName) {
    var r = rule(id)
    var m = monitorByName(monitorName)
    return r !== null && !!r["default"] && m !== null && r.monitor === m.key
  }

  function workspacesOn(monitorName) {
    return workspaceIds.filter(function(id) { return homeOf(id) === monitorName })
  }

  function iconsFor(id) {
    var list = model.windows || []
    var icons = []
    for (var i = 0; i < list.length; i++) if (list[i].workspace === id) icons.push(Icons.iconFor(list[i]["class"] || "", root.userIconRules))
    return icons
  }

  function refresh() {
    if (stateProc.running) { refreshQueued = true; return }
    stateProc.running = true
  }

  function run(args) {
    actionProc.queue.push(args)
    if (!actionProc.running) actionProc.next()
  }

  // Both actions update the model at once so the chip lands where it was
  // dropped; the next state read confirms or corrects it.
  function moveTo(id, monitorName) {
    var m = monitorByName(monitorName)
    if (!m || homeOf(id) === monitorName) return
    var rules = JSON.parse(JSON.stringify(model.rules || {}))
    var old = rules[String(id)]
    rules[String(id)] = { monitor: m.key, "default": !!(old && old.monitor === m.key && old["default"]) }
    var spaces = (model.workspaces || []).map(function(w) { return w.id === id ? { id: w.id, monitor: m.name } : w })
    model = { monitors: model.monitors, workspaces: spaces, windows: model.windows, rules: rules }
    run(["set", String(id), m.key])
  }

  function star(id, monitorName) {
    var m = monitorByName(monitorName)
    if (!m || awayFromHome(id)) return
    var rules = JSON.parse(JSON.stringify(model.rules || {}))
    for (var k in rules) if (rules[k].monitor === m.key) rules[k]["default"] = false
    rules[String(id)] = { monitor: m.key, "default": true }
    model = { monitors: model.monitors, workspaces: model.workspaces, windows: model.windows, rules: rules }
    run(["star", String(id), m.key])
  }

  function cardAt(point) {
    for (var i = 0; i < cardRepeater.count; i++) {
      var card = cardRepeater.itemAt(i)
      if (!card) continue
      var p = card.mapFromItem(dragLayer, point.x, point.y)
      if (p.x >= 0 && p.y >= 0 && p.x <= card.width && p.y <= card.height) return card.monitorName
    }
    return ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: Quickshell.execDetached([script, "install-launcher"])

  onOpenedChanged: {
    if (opened) {
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      dragWs = -1
      dropTarget = ""
    }
  }

  Process {
    id: stateProc
    command: [root.script, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          // A drag in progress keeps its picture of the world until it lands.
          if (root.dragWs < 0) root.model = parsed
        } catch (e) {
          console.warn("drorko.workspace-monitors: bad state:", e)
        }
      }
    }
    onExited: {
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: actionProc
    property var queue: []
    function next() {
      if (queue.length === 0) { root.refresh(); return }
      command = [root.script].concat(queue.shift())
      running = true
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("drorko.workspace-monitors:", text.trim())
    }
    onExited: next()
  }

  // Windows opening, closing and moving change the glyphs; monitors coming
  // and going change the cards.
  Connections {
    target: Hyprland
    function onRawEvent(event) { if (root.opened) refreshDebounce.restart() }
  }

  Timer {
    id: refreshDebounce
    interval: 150
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰕰"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Unlike the height helper, the width one does not add the card's own
    // padding and border, so they are added here.
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(240), cardsRow.implicitWidth)
                                           + panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Workspaces"
          meta: root.monitors.length > 1 ? "Drag to move · click to set " + root.starGlyph : "Click to set " + root.starGlyph
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰕰"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Row {
          id: cardsRow
          spacing: Style.space(10)

          Repeater {
            id: cardRepeater
            model: root.monitors

            MonitorCard {
              required property var modelData
              monitor: modelData
            }
          }
        }

        Text {
          visible: root.model.loaded === false
          width: parent.width
          text: "Rules apply now but won't survive a restart until hyprland.lua loads them. Add this line at its end:\nrequire(\"hypr.workspace-monitors\")"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: root.starGlyph + "  is the workspace a monitor shows when it connects."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          readonly property var away: root.workspaceIds.filter(function(id) { return root.awayFromHome(id) })
          visible: away.length > 0
          width: parent.width
          text: "External not connected. " + (away.length === 1 ? "Workspace " : "Workspaces ")
                + away.join(", ") + " go back to it when it's plugged in."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      // The ghost has to cross from one card into another, so it lives above
      // both rather than inside either.
      Item {
        id: dragLayer
        anchors.fill: parent
        z: 100

        WorkspaceChip {
          visible: root.dragWs >= 0
          workspaceId: Math.max(root.dragWs, 0)
          monitorName: root.dragWs >= 0 ? root.homeOf(root.dragWs) : ""
          ghost: true
          x: root.dragPoint.x - width / 2
          y: root.dragPoint.y - height / 2
        }
      }
    }
  }

  component MonitorCard: Rectangle {
    id: card
    property var monitor: null
    readonly property string monitorName: monitor ? monitor.name : ""
    readonly property bool targeted: root.dragWs >= 0 && root.dropTarget === monitorName && root.homeOf(root.dragWs) !== monitorName

    width: Style.space(190)
    implicitHeight: cardColumn.implicitHeight + Style.space(12) * 2
    height: Math.max(implicitHeight, Style.space(130))
    radius: Style.cornerRadius
    color: targeted ? Util.alpha(root.accent, 0.14) : Util.alpha(root.foreground, 0.04)
    border.width: targeted ? Math.max(1, Style.space(2)) : 1
    border.color: targeted ? root.accent : Util.alpha(root.foreground, monitor && monitor.focused ? 0.45 : 0.2)

    Column {
      id: cardColumn
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(10)

      Row {
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: card.monitor && card.monitor.laptop ? "󰌢" : "󰍹"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: card.monitor ? root.monitorTitle(card.monitor) : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: Style.space(140)
            text: card.monitor ? (card.monitor.description || card.monitor.name) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.workspacesOn(card.monitorName)

          WorkspaceChip {
            required property int modelData
            workspaceId: modelData
            monitorName: card.monitorName
          }
        }
      }

      Text {
        visible: root.workspacesOn(card.monitorName).length === 0
        text: root.monitors.length > 1 ? "Drop a workspace here" : "No workspaces"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component WorkspaceChip: Rectangle {
    id: chip
    property int workspaceId: 0
    property string monitorName: ""
    property bool ghost: false

    readonly property bool starred: root.isDefault(workspaceId, monitorName)
    readonly property bool away: root.awayFromHome(workspaceId)
    readonly property bool shownNow: {
      var m = root.monitorByName(monitorName)
      return m !== null && m.activeWorkspace === workspaceId
    }
    readonly property var icons: root.iconsFor(workspaceId)
    readonly property bool lifted: !ghost && root.dragWs === workspaceId

    width: chipRow.implicitWidth + Style.space(10) * 2
    height: Style.space(28)
    radius: Style.cornerRadius
    opacity: lifted ? 0.3 : (away ? 0.55 : 1)
    color: ghost ? Util.alpha(root.accent, 0.3)
         : mouse.containsMouse && !away ? Util.alpha(root.foreground, 0.16)
         : Util.alpha(root.foreground, shownNow ? 0.12 : 0.06)
    border.width: shownNow || ghost ? 1 : 0
    border.color: ghost ? root.accent : Util.alpha(root.foreground, 0.6)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.workspaceId === 10 ? "0" : String(chip.workspaceId)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: chip.shownNow
      }

      Text {
        visible: chip.starred
        anchors.verticalCenter: parent.verticalCenter
        text: root.starGlyph
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: chip.icons

        Loader {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          sourceComponent: modelData.heart ? heartIcon : glyphIcon

          Component {
            id: glyphIcon
            Text {
              text: modelData.glyph
              color: root.foreground
              font.family: modelData.simple ? "Simple Icons" : root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
            }
          }

          Component {
            id: heartIcon
            Canvas {
              width: Math.round(Style.font.body * 1.15)
              height: width
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = root.foreground
                ctx.beginPath()
                trace(ctx, root.heartShape.outer)
                trace(ctx, root.heartShape.inner)
                ctx.fillRule = Qt.OddEvenFill
                ctx.fill()
              }
              function trace(ctx, points) {
                ctx.moveTo(points[0].x * width, points[0].y * height)
                for (var i = 1; i < points.length; i++) ctx.lineTo(points[i].x * width, points[i].y * height)
                ctx.closePath()
              }
            }
          }
        }
      }
    }

    MouseArea {
      id: mouse
      enabled: !chip.ghost
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      cursorShape: root.dragWs === chip.workspaceId ? Qt.ClosedHandCursor
                 : chip.away ? Qt.ArrowCursor : Qt.PointingHandCursor
      property point pressAt: Qt.point(0, 0)

      onPressed: function(event) { pressAt = Qt.point(event.x, event.y) }

      onPositionChanged: function(event) {
        if (!pressed || root.monitors.length < 2) return
        if (root.dragWs !== chip.workspaceId
            && Math.abs(event.x - pressAt.x) + Math.abs(event.y - pressAt.y) < Style.space(6)) return
        root.dragWs = chip.workspaceId
        root.dragPoint = mapToItem(dragLayer, event.x, event.y)
        root.dropTarget = root.cardAt(root.dragPoint)
      }

      onReleased: function(event) {
        if (root.dragWs === chip.workspaceId) {
          var target = root.dropTarget
          var id = chip.workspaceId
          root.dragWs = -1
          root.dropTarget = ""
          if (target !== "") root.moveTo(id, target)
          else root.refresh()
        } else {
          root.star(chip.workspaceId, chip.monitorName)
        }
      }

      onCanceled: {
        root.dragWs = -1
        root.dropTarget = ""
      }
    }
  }
}
