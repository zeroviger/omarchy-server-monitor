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
  // "auto" follows the system locale; otherwise one of the keys of `strings`.
  readonly property string language: {
    var wanted = String(setting("language", "auto"))
    if (strings[wanted] !== undefined) return wanted
    var locale = Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || Qt.locale().name
    var code = String(locale).slice(0, 2).toLowerCase()
    return strings[code] !== undefined ? code : "en"
  }
  // Registration expiry changes rarely and registries rate-limit lookups,
  // so domains are rechecked every 6 hours unless a check is forced.
  readonly property int domainRecheckMs: 6 * 3600 * 1000

  readonly property var typeOptions: [
    { value: "ping", label: "Ping" },
    { value: "tcp", label: "TCP" },
    { value: "http", label: "Web" },
    { value: "domain", label: tr("typeDomain") }
  ]
  readonly property var typeLabels: ({ ping: "ping", tcp: "TCP", http: tr("typeWebLower"), domain: tr("typeDomainLower") })

  // User-visible text, one table per language. English is the fallback for
  // missing keys. %1, %2 are replaced by the arguments of tr().
  readonly property var strings: ({
    en: {
      typeDomain: "Domain", typeDomainLower: "domain", typeWebLower: "web",
      none: "n/a", expired: "expired", days: "%1 d", offline: "offline",
      expiresOn: ", expires on %1", expiryUnpublished: ", expiry not published",
      invalidFile: "Invalid server-monitor.json: %1",
      badUrl: "Enter a valid web address, e.g. https://example.com.",
      badDomain: "Enter a valid domain, e.g. example.com.",
      badHost: "Enter a valid IP or hostname.",
      badPort: "The port must be a number between 1 and 65535.",
      duplicate: "%1 (%2) is already in the list.",
      domainRenewed: "%1: domain renewed", domainExpired: "%1: domain expired",
      domainExpiring: "%1: domain expires in %2 days",
      backOnline: "%1 is back online", isOffline: "%1 is offline",
      noServers: "Server Monitor: no servers", tooltipCounts: "%1 online, %2 offline",
      online: "online", offlineLabel: "offline", checkNow: "Check now", emptyList: "No servers. Add one below.",
      checksCount: "%1 checks", moveGroupUp: "Move group up", moveGroupDown: "Move group down",
      moveUp: "Move up", moveDown: "Move down", edit: "Edit", remove: "Remove",
      editHeader: "EDIT SERVER", addHeader: "ADD SERVER",
      name: "Name", url: "URL", domainField: "Domain", hostField: "IP or hostname", port: "Port",
      save: "Save", add: "Add", cancel: "Cancel",
      hintPing: "ICMP ping to the IP or hostname.",
      hintTcp: "TCP connection to the given port: useful if the server blocks ping.",
      hintHttp: "Green if the address answers with a 2xx or 3xx code. Without http:// or https:// it uses HTTPS.",
      hintDomain: "Registration expiry (RDAP/whois), rechecked every 6 hours. Red if fewer than %1 days are left. Grey if the registry does not publish the expiry."
    },
    it: {
      typeDomain: "Dominio", typeDomainLower: "dominio", typeWebLower: "web",
      none: "n/d", expired: "scaduto", days: "%1 gg", offline: "offline",
      expiresOn: ", scade il %1", expiryUnpublished: ", scadenza non pubblicata",
      invalidFile: "server-monitor.json non valido: %1",
      badUrl: "Inserisci un indirizzo web valido, ad esempio https://example.com.",
      badDomain: "Inserisci un dominio valido, ad esempio example.com.",
      badHost: "Inserisci un IP o un hostname valido.",
      badPort: "La porta deve essere un numero tra 1 e 65535.",
      duplicate: "%1 (%2) è già nella lista.",
      domainRenewed: "%1: dominio rinnovato", domainExpired: "%1: dominio scaduto",
      domainExpiring: "%1: il dominio scade tra %2 giorni",
      backOnline: "%1 è tornato online", isOffline: "%1 è offline",
      noServers: "Server Monitor: nessun server", tooltipCounts: "%1 online, %2 offline",
      online: "online", offlineLabel: "offline", checkNow: "Controlla ora", emptyList: "Nessun server. Aggiungine uno qui sotto.",
      checksCount: "%1 controlli", moveGroupUp: "Sposta il gruppo su", moveGroupDown: "Sposta il gruppo giù",
      moveUp: "Sposta su", moveDown: "Sposta giù", edit: "Modifica", remove: "Rimuovi",
      editHeader: "MODIFICA SERVER", addHeader: "AGGIUNGI SERVER",
      name: "Nome", url: "URL", domainField: "Dominio", hostField: "IP o hostname", port: "Porta",
      save: "Salva", add: "Aggiungi", cancel: "Annulla",
      hintPing: "Ping ICMP verso l'IP o l'hostname.",
      hintTcp: "Connessione TCP alla porta indicata: utile se il server blocca il ping.",
      hintHttp: "Verde se l'indirizzo risponde con un codice 2xx o 3xx. Senza http:// o https:// usa HTTPS.",
      hintDomain: "Scadenza della registrazione (RDAP/whois), ricontrollata ogni 6 ore. Rosso se mancano meno di %1 giorni. Grigio se il registro non pubblica la scadenza."
    },
    tr: {
      typeDomain: "Alan adı", typeDomainLower: "alan adı", typeWebLower: "web",
      none: "yok", expired: "süresi doldu", days: "%1 gün", offline: "çevrimdışı",
      expiresOn: ", bitiş: %1", expiryUnpublished: ", bitiş tarihi yayımlanmıyor",
      invalidFile: "Geçersiz server-monitor.json: %1",
      badUrl: "Geçerli bir web adresi girin, örneğin https://example.com.",
      badDomain: "Geçerli bir alan adı girin, örneğin example.com.",
      badHost: "Geçerli bir IP veya ana makine adı girin.",
      badPort: "Port 1 ile 65535 arasında bir sayı olmalı.",
      duplicate: "%1 (%2) zaten listede.",
      domainRenewed: "%1: alan adı yenilendi", domainExpired: "%1: alan adının süresi doldu",
      domainExpiring: "%1: alan adının süresi %2 gün içinde doluyor",
      backOnline: "%1 yeniden çevrimiçi", isOffline: "%1 çevrimdışı",
      noServers: "Server Monitor: sunucu yok", tooltipCounts: "%1 çevrimiçi, %2 çevrimdışı",
      online: "çevrimiçi", offlineLabel: "çevrimdışı", checkNow: "Şimdi kontrol et", emptyList: "Sunucu yok. Aşağıdan bir tane ekleyin.",
      checksCount: "%1 kontrol", moveGroupUp: "Grubu yukarı taşı", moveGroupDown: "Grubu aşağı taşı",
      moveUp: "Yukarı taşı", moveDown: "Aşağı taşı", edit: "Düzenle", remove: "Kaldır",
      editHeader: "SUNUCUYU DÜZENLE", addHeader: "SUNUCU EKLE",
      name: "Ad", url: "URL", domainField: "Alan adı", hostField: "IP veya ana makine adı", port: "Port",
      save: "Kaydet", add: "Ekle", cancel: "İptal",
      hintPing: "IP veya ana makine adına ICMP ping.",
      hintTcp: "Belirtilen porta TCP bağlantısı: sunucu ping'i engelliyorsa kullanışlıdır.",
      hintHttp: "Adres 2xx veya 3xx koduyla yanıt verirse yeşil. http:// veya https:// yoksa HTTPS kullanılır.",
      hintDomain: "Kayıt bitiş tarihi (RDAP/whois), 6 saatte bir yeniden kontrol edilir. %1 günden az kaldıysa kırmızı. Kayıt kuruluşu bitiş tarihini yayımlamıyorsa gri."
    }
  })

  function tr(key) {
    var table = strings[language] || strings.en
    var text = table[key] !== undefined ? table[key] : strings.en[key]
    for (var i = 1; i < arguments.length; i++) text = text.replace("%" + i, arguments[i])
    return text
  }

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
      if (result.state === 2) return tr("none")
      if (result.value < 0) return tr("expired")
      return tr("days", result.value)
    }
    if (server.type === "http") {
      if (result.detail === "000") return tr("offline")
      return result.state === 0 ? result.detail + " · " + result.value + " ms" : "HTTP " + result.detail
    }
    return result.state === 0 ? Math.round(result.value) + " ms" : tr("offline")
  }

  // Second line of a row: address, check type and, for domains, the expiry date.
  function subtitleText(server, result) {
    var text = addressOf(server) + "  (" + typeLabels[server.type]
    if (server.type === "domain") {
      if (result && result.detail) text += tr("expiresOn", result.detail.split("-").reverse().join("/"))
      else if (result && result.state === 2) text += tr("expiryUnpublished")
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
      errorMessage = tr("invalidFile", e)
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
        errorMessage = tr("badUrl")
        return
      }
    } else if (type === "domain") {
      host = host.toLowerCase().replace(/^[a-z]+:\/\//, "").replace(/[\/:].*$/, "")
      if (!/^([a-z0-9-]+\.)+[a-z0-9-]{2,}$/.test(host)) {
        errorMessage = tr("badDomain")
        return
      }
    } else {
      if (!/^[A-Za-z0-9._:\-\[\]]+$/.test(host)) {
        errorMessage = tr("badHost")
        return
      }
      if (type === "tcp") {
        port = Number(portText)
        if (!/^\d+$/.test(portText) || port < 1 || port > 65535) {
          errorMessage = tr("badPort")
          return
        }
      }
    }
    var entry = { name: name || host, type: type, host: host, port: port }
    for (var i = 0; i < servers.length; i++) {
      if (i !== editingIndex && keyOf(servers[i]) === keyOf(entry)) {
        errorMessage = tr("duplicate", addressOf(entry), typeLabels[type])
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
      title = ok ? tr("domainRenewed", server.name)
        : result.value < 0 ? tr("domainExpired", server.name)
        : tr("domainExpiring", server.name, result.value)
    else
      title = tr(ok ? "backOnline" : "isOffline", server.name)
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
      ? tr("noServers")
      : root.tr("tooltipCounts", root.onlineCount, root.offlineCount)
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
            text: root.onlineCount + " " + root.tr("online") + " · " + root.offlineCount + " " + root.tr("offlineLabel")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            iconText: "󰑐"
            tooltipText: root.tr("checkNow")
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
              text: root.tr("emptyList")
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
                    text: root.tr("checksCount", group.modelData.items.length)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Button {
                    verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                    iconText: "󰁝"
                    tooltipText: root.tr("moveGroupUp")
                    focusable: true
                    enabled: group.index > 0
                    opacity: enabled ? 1 : 0.3
                    onClicked: root.moveGroup(group.index, -1)
                  }

                  Button {
                    verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                    iconText: "󰁅"
                    tooltipText: root.tr("moveGroupDown")
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
                      tooltipText: root.tr("moveUp")
                      focusable: true
                      enabled: group.grouped ? row.index > 0 : group.index > 0
                      opacity: enabled ? 1 : 0.3
                      onClicked: group.grouped ? root.moveWithinGroup(group.index, row.index, -1) : root.moveGroup(group.index, -1)
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰁅"
                      tooltipText: root.tr("moveDown")
                      focusable: true
                      enabled: group.grouped ? row.index < group.modelData.items.length - 1 : group.index < root.groups.length - 1
                      opacity: enabled ? 1 : 0.3
                      onClicked: group.grouped ? root.moveWithinGroup(group.index, row.index, 1) : root.moveGroup(group.index, 1)
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰏫"
                      tooltipText: root.tr("edit")
                      focusable: true
                      selected: root.editingIndex === row.serverIndex
                      onClicked: root.editingIndex === row.serverIndex ? root.cancelEdit() : root.editServer(row.serverIndex)
                    }

                    Button {
                      verticalPadding: group.grouped ? Style.space(2) : Style.spacing.controlPaddingY
                      iconText: "󰆴"
                      tooltipText: root.tr("remove")
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
          text: root.tr(root.editingIndex >= 0 ? "editHeader" : "addHeader")
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
            placeholderText: root.tr("name")
            onAccepted: hostField.forceActiveFocus()
          }
          TextField {
            id: hostField
            Layout.fillWidth: true
            Layout.minimumWidth: Style.space(130)
            Layout.preferredWidth: Style.space(140)
            placeholderText: root.tr(root.formType === "http" ? "url"
              : root.formType === "domain" ? "domainField" : "hostField")
            onAccepted: root.saveServer()
          }
          TextField {
            id: portField
            visible: root.formType === "tcp"
            Layout.preferredWidth: Style.space(70)
            placeholderText: root.tr("port")
            inputMethodHints: Qt.ImhDigitsOnly
            onAccepted: root.saveServer()
          }
          Button {
            text: root.tr(root.editingIndex >= 0 ? "save" : "add")
            focusable: true
            enabled: hostField.text.trim() !== ""
            onClicked: root.saveServer()
          }
          Button {
            visible: root.editingIndex >= 0
            iconText: "󰅖"
            tooltipText: root.tr("cancel")
            focusable: true
            onClicked: root.cancelEdit()
          }
        }

        Text {
          width: parent.width
          text: root.formType === "domain" ? root.tr("hintDomain", root.domainWarnDays)
            : root.tr(({ ping: "hintPing", tcp: "hintTcp", http: "hintHttp" })[root.formType])
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
