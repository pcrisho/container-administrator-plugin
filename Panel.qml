import QtQuick
import QtQuick.Controls
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
  property string runtimeBin: ""
  property int selectedIndex: 0
  // Accordion state: project -> true when expanded. Missing = collapsed,
  // so the panel opens compact and the user expands the projects it needs.
  property var expanded: ({})
  // Container name whose action is in flight (one action at a time).
  property string pendingActionName: ""

  // Grouped view of root.containers (compose project, ungrouped last);
  // each entry carries flatIndex for the single selection cursor.
  property var projectGroups: Model.groupByProject(root.containers)

  // "auto" | "docker" | "podman" — from the runtime setting; auto prefers
  // docker and falls back to podman when the docker daemon is unreachable.
  readonly property string runtimeSetting: String(setting("runtime", "Auto") || "Auto").toLowerCase()

  // Not readonly: the shell pushes settings updates live, so the poll
  // interval must react to changes without a restart.
  property int pollIntervalSec: Model.clampPollInterval(setting("pollIntervalSec", 10), 10)
  readonly property int runningTotal: Model.runningCount(root.containers)
  readonly property string worstDot: root.daemonUp ? Model.worstState(root.containers) : "none"

  // One Process per job; the snapshot script sections its output so a single
  // run yields the runtime in use, the ps list, the stats map and daemon
  // reachability. Args: $1 = "stats"|"bare" (docker stats is the expensive
  // part, ~2s, only needed while the panel is open), $2 = runtime preference
  // ("docker"|"podman"|anything else = auto). Auto prefers docker and falls
  // back to podman when the docker daemon is unreachable.
  readonly property string snapshotScript: [
    "RUNTIME=\"\"",
    "if [ \"$2\" = \"docker\" ] || [ \"$2\" = \"podman\" ]; then",
    "  if command -v \"$2\" >/dev/null 2>&1 && \"$2\" info >/dev/null 2>&1; then RUNTIME=\"$2\"; fi",
    "else",
    "  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then RUNTIME=docker",
    "  elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then RUNTIME=podman",
    "  fi",
    "fi",
    "echo '==RUNTIME=='",
    "echo \"$RUNTIME\"",
    "if [ -z \"$RUNTIME\" ]; then",
    "  echo '==PS=='",
    "  echo '==DAEMON=='",
    "  echo down",
    "  exit 0",
    "fi",
    "echo '==PS=='",
    "if [ \"$RUNTIME\" = \"podman\" ]; then",
    "  podman ps -a --format json 2>/dev/null",
    "else",
    "  docker ps -a --format '{{json .}}' 2>/dev/null",
    "fi",
    "if [ \"$1\" = \"stats\" ]; then",
    "  echo '==STATS=='",
    "  if [ \"$RUNTIME\" = \"podman\" ]; then",
    "    podman stats --no-stream --format json 2>/dev/null",
    "  else",
    "    docker stats --no-stream --format '{{json .}}' 2>/dev/null",
    "  fi",
    "fi",
    "echo '==DAEMON=='",
    "echo up"
  ].join("\n")

  function refresh() {
    if (root.loading) return
    root.loading = true
    // docker stats is only needed while the panel is open, where the
    // CPU/mem percentages are actually visible. The leading "cap-snapshot"
    // is the script's $0 (sh -c <script> <arg> binds the first arg to $1).
    snapshotProc.command = ["sh", "-c", root.snapshotScript, "cap-snapshot", root.opened ? "stats" : "bare", root.runtimeSetting]
    if (!snapshotProc.running) snapshotProc.running = true
  }

  function applySnapshot(raw) {
    var text = String(raw || "")
    function section(name) {
      var parts = text.split("==" + name + "==")
      if (parts.length < 2) return ""
      return parts[1].split("==PS==")[0].split("==STATS==")[0].split("==DAEMON==")[0].split("==RUNTIME==")[0]
    }
    root.runtimeBin = section("RUNTIME").trim()
    var ps = Model.parsePsLines(section("PS"))
    var stats = Model.parseStatsLines(section("STATS"))
    root.containers = Model.mergeStats(ps, stats)
    root.daemonUp = section("DAEMON").trim() === "up"
    root.loading = false
    root.clampCursor()
  }

  function runAction(name, action) {
    if (root.actionBusy || !root.daemonUp || root.runtimeBin === "") return
    root.actionBusy = true
    root.pendingActionName = name
    root.lastError = ""
    actionProc.command = [root.runtimeBin, action, name]
    actionProc.running = true
  }

  function toggleGroup(project) {
    if (root.expanded[project]) delete root.expanded[project]
    else root.expanded[project] = true
  }

  function isRowVisible(flatIndex) {
    var c = root.containers[flatIndex]
    if (!c) return false
    return root.expanded[c.project] === true
  }

  // j/k walk only rows inside expanded groups.
  function moveCursor(delta) {
    if (root.containers.length === 0) return
    var n = root.containers.length
    for (var i = 1; i <= n; i++) {
      var idx = root.selectedIndex + delta * i
      if (idx < 0 || idx >= n) continue
      if (root.isRowVisible(idx)) { root.selectedIndex = idx; return }
    }
  }

  function clampCursor() {
    if (root.containers.length === 0) {
      root.selectedIndex = 0
      return
    }
    if (root.isRowVisible(root.selectedIndex)) return
    for (var i = 0; i < root.containers.length; i++) {
      if (root.isRowVisible(i)) { root.selectedIndex = i; return }
    }
    root.selectedIndex = -1
  }

  // Keep the keyboard-selected row inside the ScrollView viewport (pattern
  // from the audio panel: j/k must not walk the selection off-screen).
  function ensureCursorVisible(item) {
    if (!item || !containerScroll) return
    var flick = containerScroll.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = Style.space(6)
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24)) {
      flick.contentY = 0
      return
    }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
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
      onStreamFinished: actionProc.actionStderr = String(text || "").trim()
    }
    onExited: {
      root.actionBusy = false
      root.pendingActionName = ""
      root.lastError = actionProc.actionStderr !== ""
        ? actionProc.actionStderr
        : (exitCode !== 0 ? "container command failed" : "")
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
        if (!root.daemonUp) return "Container runtime unavailable"
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

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

      ScrollView {
        id: containerScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: containerScroll.contentItem
          property: "interactive"
          value: column.implicitHeight > containerScroll.height
        }

      Column {
        id: column
        width: parent.width
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
          text: "Container runtime unavailable — is Docker or Podman installed and running?"
          color: Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ---------- Container list (grouped by compose project) ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.daemonUp

          Repeater {
            model: root.projectGroups

            Column {
              id: groupCol
              width: parent.width
              required property var modelData
              property var group: modelData
              readonly property bool isExpanded: root.expanded[group.project] === true

              // ---------- Group header (click to expand/collapse) ----------
              Item {
                width: parent.width
                implicitHeight: Math.max(chevron.implicitHeight, projectTitle.implicitHeight, groupCount.implicitHeight)

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.toggleGroup(groupCol.group.project)
                }

                Text {
                  id: chevron
                  text: groupCol.isExpanded ? "▾" : "▸"
                  color: Qt.darker(root.bar.foreground, 1.3)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: projectTitle
                  text: groupCol.group.project !== "" ? groupCol.group.project : "Other"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.left: chevron.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: groupCount
                  text: {
                    var running = 0
                    for (var i = 0; i < groupCol.group.containers.length; i++) {
                      if (groupCol.group.containers[i].state === "running") running++
                    }
                    return running + "/" + groupCol.group.containers.length
                  }
                  color: Qt.darker(root.bar.foreground, 1.3)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.left: projectTitle.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              // ---------- Container rows (visible only when expanded) ----------
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: groupCol.isExpanded

                Repeater {
                  model: groupCol.group.containers

                  Rectangle {
                    id: row
                    required property var modelData
                    readonly property int flatIndex: row.modelData.flatIndex
                    readonly property bool isPending: root.pendingActionName !== "" && row.modelData.name === root.pendingActionName
                    readonly property bool selected: root.selectedIndex === row.flatIndex
                    onSelectedChanged: if (row.selected) root.ensureCursorVisible(row)
                    width: parent.width
                    height: Style.space(46)
                    radius: Style.space(6)
                    opacity: row.isPending ? 0.6 : 1.0
                    color: row.selected
                      ? Qt.rgba(1, 1, 1, 0.08)
                      : "transparent"
                    border.color: row.selected
                      ? Qt.rgba(1, 1, 1, 0.15)
                      : "transparent"

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.selectedIndex = row.flatIndex
                    }

                    Item {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(8)

                      Text {
                        id: glyph
                        visible: !row.isPending
                        text: Model.stateGlyph(row.modelData.state)
                        color: Model.stateColor(row.modelData.state, row.modelData.unhealthy)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.title
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      // In-flight action spinner (one action at a time).
                      Text {
                        id: spinner
                        visible: row.isPending
                        text: "󰂅"
                        color: "#3b82f6"
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.title
                        transformOrigin: Item.Center
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimation on rotation {
                          from: 0
                          to: 360
                          duration: 900
                          loops: Animation.Infinite
                          running: spinner.visible
                        }
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
                        opacity: root.pendingActionName === "" ? 1.0 : 0.45

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
                            visible: modelData.shown && !row.isPending
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
  }

  onOpenedChanged: if (root.opened) root.refresh()
}