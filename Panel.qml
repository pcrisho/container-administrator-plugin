import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "pcrisho.container-admin"
  ipcTarget: "pcrisho.container-admin"
  // manageIpc: false — the shell's default handler would occupy the single
  // IpcHandler this target permits and only serve open/close; we declare
  // our own below to also handle state/refresh/action.
  manageIpc: false

  property var containers: []
  property bool daemonUp: false
  property bool actionBusy: false
  property bool loading: false
  property string lastError: ""
  property int selectedIndex: 0

  // Not readonly: the shell pushes settings updates live, so the poll
  // interval must react to changes without a restart.
  property int pollIntervalSec: Model.clampPollInterval(setting("pollIntervalSec", 10), 10)
  readonly property int runningTotal: Model.runningCount(root.containers)
  readonly property string worstDot: root.daemonUp ? Model.worstState(root.containers) : "none"

  // One Process per job; the snapshot script sections its output so a single
  // run yields the ps list, the stats map and daemon reachability.
  readonly property string snapshotScript: [
    "echo '==PS=='",
    "docker ps -a --format '{{json .}}' 2>/dev/null",
    "echo '==STATS=='",
    "docker stats --no-stream --format '{{json .}}' 2>/dev/null",
    "echo '==DAEMON=='",
    "docker info >/dev/null 2>&1 && echo up || echo down"
  ].join("\n")

  function refresh() {
    if (root.loading) return
    root.loading = true
    if (!snapshotProc.running) snapshotProc.running = true
  }

  function applySnapshot(raw) {
    var text = String(raw || "")
    function section(name) {
      var parts = text.split("==" + name + "==")
      if (parts.length < 2) return ""
      return parts[1].split("==PS==")[0].split("==STATS==")[0].split("==DAEMON==")[0]
    }
    var ps = Model.parsePsLines(section("PS"))
    var stats = Model.parseStatsLines(section("STATS"))
    root.containers = Model.mergeStats(ps, stats)
    root.daemonUp = section("DAEMON").trim() === "up"
    root.loading = false
    root.clampCursor()
  }

  function runAction(name, action) {
    if (root.actionBusy || !root.daemonUp) return
    root.actionBusy = true
    root.lastError = ""
    actionProc.command = ["docker", action, name]
    actionProc.running = true
  }

  function moveCursor(delta) {
    if (root.containers.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next > root.containers.length - 1) next = root.containers.length - 1
    root.selectedIndex = next
  }

  function clampCursor() {
    if (root.containers.length === 0) {
      root.selectedIndex = 0
      return
    }
    if (root.selectedIndex > root.containers.length - 1) root.selectedIndex = root.containers.length - 1
    if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function selectedAction() {
    var c = root.containers[root.selectedIndex]
    if (!c) return
    root.runAction(c.name, "restart")
  }

  IpcHandler {
    target: "pcrisho.container-admin"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function refresh() { root.refresh() }
    function state(): string {
      return root.daemonUp ? "up" : "down"
    }
    function action(name: string, action: string): string {
      root.runAction(name, action)
      return "ok"
    }
  }

  Process {
    id: snapshotProc
    command: ["sh", "-c", root.snapshotScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySnapshot(String(text))
    }
  }

  Process {
    id: actionProc
    property string actionStderr: ""
    // streamFinished always fires before exited (see Quickshell process.cpp),
    // so actionStderr is populated when onExited runs.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionStderr = String(text || "").trim()
    }
    onExited: {
      root.actionBusy = false
      root.lastError = root.actionStderr !== ""
        ? root.actionStderr
        : (exitCode !== 0 ? "docker command failed" : "")
      root.refresh()
    }
  }

  // Keep the list honest even when containers change behind the widget.
  Timer {
    interval: root.pollIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Item {
    id: buttonHost
    anchors.fill: parent

    BarIconButton {
      id: button
      anchors.fill: parent
      bar: root.bar
      text: "󰆳"
      slotSize: Style.bar.iconSlot
      tooltipText: {
        if (!root.daemonUp) return "Docker daemon unavailable"
        return root.containers.length === 0
          ? "No containers"
          : root.runningTotal + "/" + root.containers.length + " running"
      }
      onPressed: function(b) {
        if (b === Qt.RightButton) root.open()
        else if (b === Qt.MiddleButton) root.refresh()
        else root.toggle()
      }
    }

    // Status dot: green all running, yellow paused/restarting, red exited/
    // dead/unhealthy, gray daemon down or no containers.
    Text {
      anchors.top: parent.top
      anchors.right: parent.right
      text: "●"
      color: Model.dotColor(root.worstDot)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.space(8)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.selectedAction()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_J) { root.moveCursor(1); event.accepted = true }
        else if (event.key === Qt.Key_K) { root.moveCursor(-1); event.accepted = true }
        else if (event.key === Qt.Key_R) { root.refresh(); event.accepted = true }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: headerTitle.implicitHeight

          Text {
            id: headerTitle
            text: "Containers"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.loading ? "…" : root.runningTotal + "/" + root.containers.length
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.left: headerTitle.right
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "r  refresh"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Daemon down state (no silent empty list) ----------
        Text {
          width: parent.width
          visible: !root.daemonUp
          text: "Docker daemon unavailable — is the docker service running?"
          color: Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ---------- Container list ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.daemonUp

          Repeater {
            model: root.containers

            Rectangle {
              id: row
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(46)
              radius: Style.space(6)
              color: root.selectedIndex === row.index
                ? Qt.rgba(1, 1, 1, 0.08)
                : "transparent"
              border.color: root.selectedIndex === row.index
                ? Qt.rgba(1, 1, 1, 0.15)
                : "transparent"

              MouseArea {
                anchors.fill: parent
                onClicked: root.selectedIndex = row.index
              }

              Item {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)

                Text {
                  id: glyph
                  text: Model.stateGlyph(row.modelData.state)
                  color: Model.stateColor(row.modelData.state, row.modelData.unhealthy)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  id: nameCol
                  anchors.left: glyph.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: rowActions.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: row.modelData.name
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: {
                      var image = row.modelData.image
                      if (row.modelData.cpuPct >= 0) {
                        image += " · " + row.modelData.cpuPct.toFixed(1) + "% · " + row.modelData.memPct.toFixed(1) + "%"
                      }
                      if (row.modelData.unhealthy) image += " · unhealthy"
                      return image
                    }
                    color: row.modelData.unhealthy ? Color.urgent : Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: rowActions
                  spacing: Style.space(4)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter

                  readonly property var actions: [
                    { label: "Start", cmd: "start", shown: row.modelData.state !== "running" },
                    { label: "Stop", cmd: "stop", shown: row.modelData.state === "running" },
                    { label: "Restart", cmd: "restart", shown: row.modelData.state === "running" }
                  ]

                  Repeater {
                    model: rowActions.actions

                    Button {
                      required property var modelData
                      text: modelData.label
                      visible: modelData.shown
                      fontSize: Style.font.caption
                      foreground: root.bar.foreground
                      fontFamily: root.bar.fontFamily
                      horizontalPadding: Style.spacing.controlPaddingX
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      onClicked: root.runAction(row.modelData.name, modelData.cmd)
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.containers.length === 0 && root.daemonUp
            text: "No containers found"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Footer ----------
        Text {
          width: parent.width
          visible: root.lastError !== ""
          text: root.lastError
          color: Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          width: parent.width
          text: "j/k select · Enter restart · r refresh · Esc close"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  onOpenedChanged: if (root.opened) root.refresh()
}