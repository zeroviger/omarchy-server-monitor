pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Server Monitor: checks a user-defined list of servers and shows each one
// with a green (online) or red (offline) dot. Servers without a port are
// checked with ICMP ping; servers with a port with a TCP connect.
// The list lives in ~/.config/omarchy/server-monitor.json.
Panel {
  id: root
  moduleName: "giuseppe.server-monitor"
  ipcTarget: moduleName

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string storePath: home + "/.config/omarchy/server-monitor.json"
  readonly property int intervalSec: Math.max(10, Number(setting("intervalSec", 60)) || 60)
  readonly property bool notifyChanges: setting("notify", true) === true

  // [{ name, host, port }]
  property var servers: []
  // key -> { up: bool, ms: number }
  property var status: ({})
  property bool checking: false
  property bool checkPending: false
  property string errorMessage: ""
  // Index of the server being edited in the form, -1 when adding a new one.
  property int editingIndex: -1

  // Theme palette: green/red come straight from the active theme's colors.toml.
  property color okColor: Color.accent
  property color downColor: Color.urgent

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int onlineCount: countWhere(true)
  readonly property int offlineCount: countWhere(false)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function keyOf(server) {
    return server.host + (server.port ? ":" + server.port : "")
  }

  function countWhere(up) {
    var n = 0
    for (var i = 0; i < servers.length; i++) {
      var s = status[keyOf(servers[i])]
      if (s && s.up === up) n++
    }
    return n
  }

  // ---- theme ---------------------------------------------------------------

  function loadPalette(raw) {
    var values = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) values[m[1]] = m[2]
    }
    okColor = values.green || values.color2 || Color.accent
    downColor = values.red || values.color1 || Color.urgent
  }

  // The shell pushes theme switches over IPC rather than re-reading
  // colors.toml, so re-read it whenever the shell's palette changes.
  Connections {
    target: Color
    function onBackgroundChanged() { paletteFile.reload() }
    function onForegroundChanged() { paletteFile.reload() }
    function onUrgentChanged() { paletteFile.reload() }
  }

  FileView {
    id: paletteFile
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPalette(text())
    onFileChanged: reload()
  }

  // ---- storage -------------------------------------------------------------

  function loadServers(raw) {
    var list = []
    try {
      var parsed = JSON.parse(raw || "[]")
      if (Array.isArray(parsed)) {
        for (var i = 0; i < parsed.length; i++) {
          var s = parsed[i]
          if (!s || typeof s.host !== "string" || s.host === "") continue
          list.push({ name: String(s.name || s.host), host: s.host, port: s.port ? Number(s.port) : 0 })
        }
      }
    } catch (e) {
      errorMessage = "server-monitor.json non valido: " + e
    }
    servers = list
    if (editingIndex >= list.length) cancelEdit()
    check()
  }

  function saveServers() {
    storeFile.setText(JSON.stringify(servers, null, 2) + "\n")
  }

  FileView {
    id: storeFile
    path: root.storePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadServers(text())
    onLoadFailed: root.loadServers("[]")
    onFileChanged: reload()
  }

  function saveServer() {
    var name = nameField.text.trim()
    var host = hostField.text.trim()
    var portText = portField.text.trim()
    errorMessage = ""
    if (!/^[A-Za-z0-9._:\-\[\]]+$/.test(host)) {
      errorMessage = "Inserisci un IP o un hostname valido."
      return
    }
    var port = 0
    if (portText !== "") {
      port = Number(portText)
      if (!/^\d+$/.test(portText) || port < 1 || port > 65535) {
        errorMessage = "La porta deve essere un numero tra 1 e 65535."
        return
      }
    }
    var entry = { name: name || host, host: host, port: port }
    for (var i = 0; i < servers.length; i++) {
      if (i !== editingIndex && keyOf(servers[i]) === keyOf(entry)) {
        errorMessage = keyOf(entry) + " è già nella lista."
        return
      }
    }
    var next = servers.slice()
    if (editingIndex >= 0) next[editingIndex] = entry
    else next.push(entry)
    servers = next
    saveServers()
    cancelEdit()
    check()
  }

  function editServer(index) {
    var server = servers[index]
    if (!server) return
    errorMessage = ""
    editingIndex = index
    nameField.text = server.name
    hostField.text = server.host
    portField.text = server.port ? String(server.port) : ""
    nameField.forceActiveFocus()
  }

  function cancelEdit() {
    editingIndex = -1
    nameField.text = ""
    hostField.text = ""
    portField.text = ""
  }

  function moveServer(index, delta) {
    var target = index + delta
    if (target < 0 || target >= servers.length) return
    var next = servers.slice()
    var moved = next.splice(index, 1)[0]
    next.splice(target, 0, moved)
    if (editingIndex === index) editingIndex = target
    else if (editingIndex === target) editingIndex = index
    servers = next
    saveServers()
  }

  function removeServer(index) {
    var next = servers.slice()
    next.splice(index, 1)
    if (index === editingIndex) cancelEdit()
    else if (index < editingIndex) editingIndex--
    servers = next
    saveServers()
  }

  // ---- checks --------------------------------------------------------------

  readonly property string checkScript: String(Qt.resolvedUrl("check.sh")).replace(/^file:\/\//, "")

  function check() {
    if (checking) { checkPending = true; return }
    if (servers.length === 0) { status = ({}); return }
    var args = ["bash", checkScript]
    for (var i = 0; i < servers.length; i++)
      args.push(String(i), servers[i].host, String(servers[i].port || 0))
    checkProc.snapshot = servers.slice()
    checkProc.command = args
    checking = true
    checkProc.running = true
  }

  function finishCheck(output) {
    var list = checkProc.snapshot
    var next = {}
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length < 3) continue
      var server = list[Number(parts[0])]
      if (!server) continue
      next[keyOf(server)] = { up: parts[1] === "0", ms: Number(parts[2]) || 0 }
    }
    if (notifyChanges) {
      for (var j = 0; j < list.length; j++) {
        var key = keyOf(list[j])
        var before = status[key]
        var after = next[key]
        if (before && after && before.up !== after.up)
          notify(list[j], after.up)
      }
    }
    status = next
    checking = false
    if (checkPending) {
      checkPending = false
      Qt.callLater(root.check)
    }
  }

  function notify(server, up) {
    Quickshell.execDetached(["notify-send", "-a", "Server Monitor",
      "-u", up ? "normal" : "critical",
      server.name + (up ? " è tornato online" : " è offline"),
      keyOf(server)])
  }

  onOpenedChanged: {
    if (opened) return
    cancelEdit()
    errorMessage = ""
  }

  Process {
    id: checkProc
    property var snapshot: []
    stdout: StdioCollector { id: checkOut }
    onExited: root.finishCheck(checkOut.text)
  }

  Timer {
    interval: root.intervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.check()
  }

  // ---- bar button ----------------------------------------------------------

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.servers.length === 0 || (root.bar && root.bar.vertical)
      ? "󰒍"
      : "󰒍 " + root.onlineCount + "/" + root.servers.length
    active: root.offlineCount > 0
    tooltipText: root.servers.length === 0
      ? "Server Monitor: nessun server"
      : root.onlineCount + " online, " + root.offlineCount + " offline"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.check()
      else root.toggle()
    }
  }

  // ---- popup ---------------------------------------------------------------

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: focusArea
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(Math.min(content.implicitHeight, Style.space(600)))

    Item {
      id: focusArea
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.editingIndex >= 0) root.cancelEdit()
          else root.close()
          event.accepted = true
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "Server Monitor"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Text {
            visible: root.servers.length > 0
            text: root.onlineCount + " online · " + root.offlineCount + " offline"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            iconText: "󰑐"
            tooltipText: "Controlla ora"
            focusable: true
            iconSpinning: root.checking
            onClicked: root.check()
          }
        }

        Text {
          width: parent.width
          visible: root.errorMessage !== ""
          text: root.errorMessage
          textFormat: Text.PlainText
          color: root.downColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Flickable {
          width: parent.width
          height: Math.min(serverList.implicitHeight, Style.space(380))
          contentHeight: serverList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: serverList
            width: parent.width
            spacing: Style.space(4)

            Text {
              visible: root.servers.length === 0
              text: "Nessun server. Aggiungine uno qui sotto."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.servers

              Column {
                id: row
                required property var modelData
                required property int index
                readonly property var result: root.status[root.keyOf(modelData)]
                readonly property bool known: result !== undefined
                width: serverList.width
                spacing: Style.space(4)

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Util.alpha(root.foreground, 0.2)
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Rectangle {
                    id: dot
                    Layout.preferredWidth: Style.space(10)
                    Layout.preferredHeight: Style.space(10)
                    Layout.alignment: Qt.AlignVCenter
                    radius: width / 2
                    color: !row.known ? Color.muted : (row.result.up ? root.okColor : root.downColor)

                    SequentialAnimation on opacity {
                      running: root.checking && !row.known
                      loops: Animation.Infinite
                      alwaysRunToEnd: true
                      NumberAnimation { to: 0.3; duration: 500 }
                      NumberAnimation { to: 1.0; duration: 500 }
                    }
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      width: parent.width
                      text: row.modelData.name
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: root.keyOf(row.modelData) + (row.modelData.port ? "  (TCP)" : "  (ping)")
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    text: !row.known ? "…" : (row.result.up ? Math.round(row.result.ms) + " ms" : "offline")
                    textFormat: Text.PlainText
                    color: !row.known ? root.dim : (row.result.up ? root.foreground : root.downColor)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Button {
                    iconText: "󰁝"
                    tooltipText: "Sposta su"
                    focusable: true
                    enabled: row.index > 0
                    opacity: enabled ? 1 : 0.3
                    onClicked: root.moveServer(row.index, -1)
                  }

                  Button {
                    iconText: "󰁅"
                    tooltipText: "Sposta giù"
                    focusable: true
                    enabled: row.index < root.servers.length - 1
                    opacity: enabled ? 1 : 0.3
                    onClicked: root.moveServer(row.index, 1)
                  }

                  Button {
                    iconText: "󰏫"
                    tooltipText: "Modifica"
                    focusable: true
                    selected: root.editingIndex === row.index
                    onClicked: root.editingIndex === row.index ? root.cancelEdit() : root.editServer(row.index)
                  }

                  Button {
                    iconText: "󰆴"
                    tooltipText: "Rimuovi"
                    focusable: true
                    onClicked: root.removeServer(row.index)
                  }
                }
              }
            }
          }
        }

        PanelSectionHeader {
          text: root.editingIndex >= 0 ? "MODIFICA SERVER" : "AGGIUNGI SERVER"
          foreground: root.foreground
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: nameField
            Layout.fillWidth: true
            Layout.preferredWidth: Style.space(170)
            placeholderText: "Nome"
            onAccepted: hostField.forceActiveFocus()
          }
          TextField {
            id: hostField
            Layout.fillWidth: true
            Layout.minimumWidth: Style.space(130)
            Layout.preferredWidth: Style.space(140)
            placeholderText: "IP o hostname"
            onAccepted: root.saveServer()
          }
          TextField {
            id: portField
            Layout.preferredWidth: Style.space(70)
            placeholderText: "Porta"
            inputMethodHints: Qt.ImhDigitsOnly
            onAccepted: root.saveServer()
          }
          Button {
            text: root.editingIndex >= 0 ? "Salva" : "Aggiungi"
            focusable: true
            enabled: hostField.text.trim() !== ""
            onClicked: root.saveServer()
          }
          Button {
            visible: root.editingIndex >= 0
            iconText: "󰅖"
            tooltipText: "Annulla"
            focusable: true
            onClicked: root.cancelEdit()
          }
        }

        Text {
          width: parent.width
          text: "Senza porta: ping ICMP. Con porta: connessione TCP (utile se il server blocca il ping)."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
