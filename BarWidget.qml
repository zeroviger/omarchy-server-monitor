pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Server Monitor: checks a user-defined list of servers and shows each one
// with a green (ok) or red (down) dot. Each entry has a type: ICMP ping, TCP
// connect, web (HTTP/HTTPS status) or domain (registration expiry).
// The list lives in ~/.config/omarchy/server-monitor.json.
Panel {
  id: root
  moduleName: "mcp64.server-monitor"
  ipcTarget: moduleName

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string storePath: home + "/.config/omarchy/server-monitor.json"
  readonly property int intervalSec: Math.max(10, Number(setting("intervalSec", 60)) || 60)
  readonly property bool notifyChanges: setting("notify", true) === true
  readonly property int domainWarnDays: Math.max(0, Number(setting("domainWarnDays", 30)) || 0)
  // Registration expiry changes rarely and registries rate-limit lookups,
  // so domains are rechecked every 6 hours unless a check is forced.
  readonly property int domainRecheckMs: 6 * 3600 * 1000

  readonly property var typeOptions: [
    { value: "ping", label: "Ping" },
    { value: "tcp", label: "TCP" },
    { value: "http", label: "Web" },
    { value: "domain", label: "Dominio" }
  ]
  readonly property var typeLabels: ({ ping: "ping", tcp: "TCP", http: "web", domain: "dominio" })

  // [{ name, type, host, port }]
  property var servers: []
  // key -> { state: 0 ok | 1 down | 2 unknown, value: number, detail: string, at: ms }
  property var status: ({})
  // Type selected in the add/edit form.
  property string formType: "ping"
  property bool checking: false
  property bool checkPending: false
  property bool checkForced: false
  property string errorMessage: ""
  // Index of the server being edited in the form, -1 when adding a new one.
  property int editingIndex: -1

  // Theme palette: green/red come straight from the active theme's colors.toml.
  property color okColor: Color.accent
  property color downColor: Color.urgent

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int onlineCount: countWhere(0)
  readonly property int offlineCount: countWhere(1)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function keyOf(server) {
    return server.type + "|" + server.host + "|" + (server.port || 0)
  }

  function addressOf(server) {
    return server.type === "tcp" ? server.host + ":" + server.port : server.host
  }

  function groupKey(server) {
    return String(server.name).trim().toLowerCase()
  }

  // Entries sharing a name (case-insensitive) form a group; groups keep the
  // order in which their first entry appears.
  function groupList(list) {
    var groups = []
    var byKey = {}
    for (var i = 0; i < list.length; i++) {
      var key = groupKey(list[i])
      if (byKey[key] === undefined) {
        byKey[key] = groups.length
        groups.push({ name: list[i].name, items: [] })
      }
      groups[byKey[key]].items.push(list[i])
    }
    return groups
  }

  function flatten(groups) {
    var list = []
    for (var i = 0; i < groups.length; i++) list = list.concat(groups[i].items)
    return list
  }

  function dotColor(result) {
    return !result || result.state === 2 ? Color.muted : (result.state === 0 ? okColor : downColor)
  }

  // Worst state in a group: any problem is red, all ok is green, else unknown.
  function groupState(items) {
    var allOk = true
    for (var i = 0; i < items.length; i++) {
      var s = status[keyOf(items[i].server)]
      if (s && s.state === 1) return 1
      if (!s || s.state !== 0) allOk = false
    }
    return allOk ? 0 : 2
  }

  // servers is kept grouped (members of a group are contiguous), so each
  // group maps to a run of indices in it.
  readonly property var groups: {
    var list = groupList(servers)
    var index = 0
    return list.map(function(group) {
      return {
        name: group.name,
        items: group.items.map(function(server) { return { server: server, index: index++ } })
      }
    })
  }

  // Replace the list, regroup it, keep the entry being edited and save.
  function setServers(next) {
    var editing = editingIndex >= 0 ? servers[editingIndex] : null
    servers = flatten(groupList(next))
    editingIndex = editing ? servers.indexOf(editing) : -1
    saveServers()
  }

  function countWhere(state) {
    var n = 0
    for (var i = 0; i < servers.length; i++) {
      var s = status[keyOf(servers[i])]
      if (s && s.state === state) n++
    }
    return n
  }

  // Text shown on the right of a row.
  function resultText(server, result) {
    if (!result) return "…"
    if (server.type === "domain") {
      if (result.state === 2) return "n/d"
      if (result.value < 0) return "scaduto"
      return result.value + " gg"
    }
    if (server.type === "http") {
      if (result.detail === "000") return "offline"
      return result.state === 0 ? result.detail + " · " + result.value + " ms" : "HTTP " + result.detail
    }
    return result.state === 0 ? Math.round(result.value) + " ms" : "offline"
  }

  // Second line of a row: address, check type and, for domains, the expiry date.
  function subtitleText(server, result) {
    var text = addressOf(server) + "  (" + typeLabels[server.type]
    if (server.type === "domain") {
      if (result && result.detail) text += ", scade il " + result.detail.split("-").reverse().join("/")
      else if (result && result.state === 2) text += ", scadenza non pubblicata"
    }
    return text + ")"
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
          var port = s.port ? Number(s.port) : 0
          // Entries saved before types existed: a port meant TCP.
          var type = typeLabels[s.type] !== undefined ? s.type : (port ? "tcp" : "ping")
          list.push({ name: String(s.name || s.host), type: type, host: s.host, port: type === "tcp" ? port : 0 })
        }
      }
    } catch (e) {
      errorMessage = "server-monitor.json non valido: " + e
    }
    servers = flatten(groupList(list))
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
    var type = formType
    var name = nameField.text.trim()
    var host = hostField.text.trim()
    var portText = portField.text.trim()
    var port = 0
    errorMessage = ""
    if (type === "http") {
      if (!/^(https?:\/\/)?[A-Za-z0-9.\-]+(:\d{1,5})?(\/\S*)?$/i.test(host)) {
        errorMessage = "Inserisci un indirizzo web valido, ad esempio https://example.com."
        return
      }
    } else if (type === "domain") {
      host = host.toLowerCase().replace(/^[a-z]+:\/\//, "").replace(/[\/:].*$/, "")
      if (!/^([a-z0-9-]+\.)+[a-z0-9-]{2,}$/.test(host)) {
        errorMessage = "Inserisci un dominio valido, ad esempio example.com."
        return
      }
    } else {
      if (!/^[A-Za-z0-9._:\-\[\]]+$/.test(host)) {
        errorMessage = "Inserisci un IP o un hostname valido."
        return
      }
      if (type === "tcp") {
        port = Number(portText)
        if (!/^\d+$/.test(portText) || port < 1 || port > 65535) {
          errorMessage = "La porta deve essere un numero tra 1 e 65535."
          return
        }
      }
    }
    var entry = { name: name || host, type: type, host: host, port: port }
    for (var i = 0; i < servers.length; i++) {
      if (i !== editingIndex && keyOf(servers[i]) === keyOf(entry)) {
        errorMessage = addressOf(entry) + " (" + typeLabels[type] + ") è già nella lista."
        return
      }
    }
    var next = servers.slice()
    if (editingIndex >= 0) next[editingIndex] = entry
    else next.push(entry)
    cancelEdit()
    setServers(next)
    check()
  }

  function editServer(index) {
    var server = servers[index]
    if (!server) return
    errorMessage = ""
    editingIndex = index
    formType = server.type
    nameField.text = server.name
    hostField.text = server.host
    portField.text = server.port ? String(server.port) : ""
    nameField.forceActiveFocus()
  }

  function cancelEdit() {
    editingIndex = -1
    formType = "ping"
    nameField.text = ""
    hostField.text = ""
    portField.text = ""
  }

  function swap(list, index, delta) {
    var target = index + delta
    if (target < 0 || target >= list.length) return false
    var moved = list[index]
    list[index] = list[target]
    list[target] = moved
    return true
  }

  // Move a whole group up or down past its neighbour.
  function moveGroup(groupIndex, delta) {
    var list = groupList(servers)
    if (swap(list, groupIndex, delta)) setServers(flatten(list))
  }

  // Move one entry up or down inside its group.
  function moveWithinGroup(groupIndex, itemIndex, delta) {
    var list = groupList(servers)
    if (swap(list[groupIndex].items, itemIndex, delta)) setServers(flatten(list))
  }

  function removeServer(index) {
    var next = servers.slice()
    next.splice(index, 1)
    if (index === editingIndex) cancelEdit()
    setServers(next)
  }

  // ---- checks --------------------------------------------------------------

  readonly property string checkScript: String(Qt.resolvedUrl("check.sh")).replace(/^file:\/\//, "")

  // force: also recheck domains whose expiry was looked up recently.
  function check(force) {
    if (checking) { checkPending = true; checkForced = checkForced || force === true; return }
    if (servers.length === 0) { status = ({}); return }
    var args = ["bash", checkScript, String(domainWarnDays)]
    var now = Date.now()
    for (var i = 0; i < servers.length; i++) {
      var server = servers[i]
      var known = status[keyOf(server)]
      if (server.type === "domain" && force !== true && known && now - known.at < domainRecheckMs) continue
      args.push(String(i), server.type, server.host, String(server.port || 0))
    }
    checkProc.snapshot = servers.slice()
    checkProc.command = args
    checking = true
    checkProc.running = true
  }

  function finishCheck(output) {
    var list = checkProc.snapshot
    var next = {}
    // Keep results for entries this run skipped (recently checked domains).
    for (var k = 0; k < list.length; k++) {
      var kept = status[keyOf(list[k])]
      if (kept) next[keyOf(list[k])] = kept
    }
    var fresh = {}
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length < 4) continue
      var server = list[Number(parts[0])]
      if (!server) continue
      var key = keyOf(server)
      next[key] = { state: Number(parts[1]), value: Number(parts[2]) || 0, detail: parts[3], at: Date.now() }
      fresh[key] = true
    }
    if (notifyChanges) {
      for (var j = 0; j < list.length; j++) {
        var jkey = keyOf(list[j])
        var before = status[jkey]
        var after = next[jkey]
        if (fresh[jkey] && before && after && before.state !== after.state && before.state !== 2 && after.state !== 2)
          notify(list[j], after)
      }
    }
    status = next
    checking = false
    if (checkPending) {
      var forced = checkForced
      checkPending = false
      checkForced = false
      Qt.callLater(function() { root.check(forced) })
    }
  }

  function notify(server, result) {
    var ok = result.state === 0
    var title
    if (server.type === "domain")
      title = ok ? server.name + ": dominio rinnovato"
        : server.name + (result.value < 0 ? ": dominio scaduto" : ": il dominio scade tra " + result.value + " giorni")
    else
      title = server.name + (ok ? " è tornato online" : " è offline")
    Quickshell.execDetached(["notify-send", "-a", "Server Monitor",
      "-u", ok ? "normal" : "critical", title, addressOf(server)])
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
      if (mouseButton === Qt.MiddleButton) root.check(true)
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
    contentWidth: popup.fittedContentWidth(Style.space(660))
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
            onClicked: root.check(true)
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
              model: root.groups

              Column {
                id: group
                required property var modelData
                required property int index
                readonly property bool grouped: modelData.items.length > 1
                readonly property int state: root.groupState(modelData.items)
                width: serverList.width
                spacing: grouped ? Style.space(1) : Style.space(4)

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Util.alpha(root.foreground, 0.2)
                }

                // Group header, only when several checks share the name.
                RowLayout {
                  visible: group.grouped
                  width: parent.width
                  spacing: Style.space(8)

                  Rectangle {
                    Layout.preferredWidth: Style.space(10)
                    Layout.preferredHeight: Style.space(10)
                    Layout.alignment: Qt.AlignVCenter
                    radius: width / 2
                    color: group.state === 2 ? Color.muted : (group.state === 0 ? root.okColor : root.downColor)
                  }

                  Text {
                    Layout.fillWidth: true
                    text: group.modelData.name
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: group.modelData.items.length + " controlli"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Button {
                    verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                    iconText: "󰁝"
                    tooltipText: "Sposta il gruppo su"
                    focusable: true
                    enabled: group.index > 0
                    opacity: enabled ? 1 : 0.3
                    onClicked: root.moveGroup(group.index, -1)
                  }

                  Button {
                    verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                    iconText: "󰁅"
                    tooltipText: "Sposta il gruppo giù"
                    focusable: true
                    enabled: group.index < root.groups.length - 1
                    opacity: enabled ? 1 : 0.3
                    onClicked: root.moveGroup(group.index, 1)
                  }

                  // Invisible spacers so the arrows line up with the rows below.
                  Button { iconText: "󰏫"; enabled: false; opacity: 0; verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY }
                  Button { iconText: "󰆴"; enabled: false; opacity: 0; verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY }
                }

                Repeater {
                  model: group.modelData.items

                  RowLayout {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var server: modelData.server
                    readonly property int serverIndex: modelData.index
                    readonly property var result: root.status[root.keyOf(server)]
                    readonly property bool known: result !== undefined
                    width: group.width
                    spacing: Style.space(8)

                    Item {
                      visible: group.grouped
                      Layout.preferredWidth: Style.space(10)
                    }

                    component StatusDot: Rectangle {
                      width: Style.space(10)
                      height: Style.space(10)
                      radius: width / 2
                      color: root.dotColor(row.result)

                      SequentialAnimation on opacity {
                        running: root.checking && !row.known
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.3; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                      }
                    }

                    // Inside a group: the dot sits beside the single line of the check.
                    StatusDot {
                      visible: group.grouped
                      Layout.preferredWidth: width
                      Layout.preferredHeight: height
                      Layout.alignment: Qt.AlignVCenter
                    }

                    Column {
                      Layout.fillWidth: true
                      spacing: 0

                      // Single entry: the dot sits on the name line, the address below the name.
                      Row {
                        visible: !group.grouped
                        width: parent.width
                        spacing: Style.space(8)

                        StatusDot {
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          width: parent.width - Style.space(10) - parent.spacing
                          text: row.server.name
                          textFormat: Text.PlainText
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.bold: true
                          elide: Text.ElideRight
                        }
                      }
                      Text {
                        width: parent.width
                        leftPadding: group.grouped ? 0 : Style.space(10) + Style.space(8)
                        text: root.subtitleText(row.server, row.result)
                        textFormat: Text.PlainText
                        color: group.grouped ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: group.grouped ? Style.font.bodySmall : Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      text: root.resultText(row.server, row.result)
                      textFormat: Text.PlainText
                      color: !row.known || row.result.state === 2 ? root.dim : (row.result.state === 0 ? root.foreground : root.downColor)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰁝"
                      tooltipText: "Sposta su"
                      focusable: true
                      enabled: group.grouped ? row.index > 0 : group.index > 0
                      opacity: enabled ? 1 : 0.3
                      onClicked: group.grouped ? root.moveWithinGroup(group.index, row.index, -1) : root.moveGroup(group.index, -1)
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰁅"
                      tooltipText: "Sposta giù"
                      focusable: true
                      enabled: group.grouped ? row.index < group.modelData.items.length - 1 : group.index < root.groups.length - 1
                      opacity: enabled ? 1 : 0.3
                      onClicked: group.grouped ? root.moveWithinGroup(group.index, row.index, 1) : root.moveGroup(group.index, 1)
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰏫"
                      tooltipText: "Modifica"
                      focusable: true
                      selected: root.editingIndex === row.serverIndex
                      onClicked: root.editingIndex === row.serverIndex ? root.cancelEdit() : root.editServer(row.serverIndex)
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰆴"
                      tooltipText: "Rimuovi"
                      focusable: true
                      onClicked: root.removeServer(row.serverIndex)
                    }
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

        ButtonGroup {
          options: root.typeOptions
          value: root.formType
          fontSize: Style.font.bodySmall
          onChanged: function(value) { root.formType = value }
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
            placeholderText: root.formType === "http" ? "URL"
              : root.formType === "domain" ? "Dominio" : "IP o hostname"
            onAccepted: root.saveServer()
          }
          TextField {
            id: portField
            visible: root.formType === "tcp"
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
          text: ({
            ping: "Ping ICMP verso l'IP o l'hostname.",
            tcp: "Connessione TCP alla porta indicata: utile se il server blocca il ping.",
            http: "Verde se l'indirizzo risponde con un codice 2xx o 3xx. Senza http:// o https:// usa HTTPS.",
            domain: "Scadenza della registrazione (RDAP/whois), ricontrollata ogni 6 ore. Rosso se mancano meno di "
              + root.domainWarnDays + " giorni. Grigio se il registro non pubblica la scadenza."
          })[root.formType]
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
