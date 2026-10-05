pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property string uiVersion: "0.3.0"
  property size preferredSize: Qt.size(1120, 740)
  property bool detailActive: false
  property bool includeRemoved: false
  property string searchQuery: ""
  readonly property bool wideLayout: window.width >= 900
  property bool opened: false
  property string helper: decodeURIComponent(Qt.resolvedUrl("bin/myomarchy").toString().replace("file://", ""))
  property var records: []
  property var selected: null
  property string detailIdentity: ""
  onSelectedChanged: {
    var identity = selected && selected.id ? selected.id : ""
    if (!identity || identity !== detailIdentity) {
      detailIdentity = identity
      Qt.callLater(function() { if (detailScroll.contentItem) detailScroll.contentItem.contentY = 0 })
    }
  }
  property var recovery: ({ready: false, missing: ["/", "/home"]})
  property string tab: "plugins"
  property string request: ""
  property string message: ""
  property bool working: false
  property bool refreshPending: false
  property bool updating: false
  property bool exited: false
  property bool outputDone: false
  property bool errorsDone: false
  property int exitCode: 0
  readonly property color ink: Color.foreground
  readonly property color paper: Color.background
  function open() {
    opened = true
    if (working) refreshPending = true
    else call("refresh", [])
  }
  function backToList() { detailActive = false; Qt.callLater(function() { list.forceActiveFocus() }) }
  function selectRecord(id) {
    detailActive = true
    if (!wideLayout) Qt.callLater(function() { backAction.forceActiveFocus() })
    call("show", [id])
  }
  function versionInfo() { return uiVersion }
  function close() { opened = false }
  function toggle() { opened ? close() : open() }
  function call(action, args, preserveMessage) {
    if (working) return
    request = action; working = true
    if (!preserveMessage) message = ""
    exited = false; outputDone = false; errorsDone = false
    backend.command = ["python3", helper, action].concat(args)
    backend.running = true
  }
  function visibleRecords() {
    return records.filter(function(r) {
      return (tab === "activity" || r.category === tab)
        && (root.includeRemoved || r.status !== "removed")
        && (!root.searchQuery || r.title.toLowerCase().indexOf(root.searchQuery.toLowerCase()) >= 0)
    })
  }
  function dateLabel(r, compact) {
    if (!r.date) return "Date evidence unavailable"
    var date = r.date
    if (r.date.indexOf("T") >= 0) {
      var moment = new Date(r.date)
      date = compact ? moment.getFullYear() + "-" + ("0" + (moment.getMonth()+1)).slice(-2) + "-" + ("0" + moment.getDate()).slice(-2) : moment.toLocaleString()
    }
    if (r.date_kind === "inferred-install") return "Installed ≈ " + date
    if (r.date_kind === "location-created") return "Location created " + date
    if (r.date_kind === "first-seen") return "Present by " + date
    return (r.date_kind === "installed" ? "Installed " : r.date_kind === "logged" ? "Logged " : "Recorded ") + date
  }
  function detailsText(r) {
    if (!r) return "Browse installed plugins, agent fixes, customizations, and routine package activity.\n\nRefresh imports your existing journal and observes current plugins. It does not run installations or open an agent."
    var detail = r.details || ""
    if (r.origin === "discovered") {
      try {
        var plugin = JSON.parse(detail)
        detail = "Version: " + (plugin.version || "unknown") + "\nAuthor: " + (plugin.author || "unspecified") + "\nPlugin: " + plugin.plugin_id + "\nLocation: " + plugin.path
      } catch (e) {}
    }
    return detail + "\n\n" + (r.events || []).map(function(e) {
      var value
      try { value = JSON.parse(e.details) } catch (err) { return e.at + " · " + e.kind }
      var description = value.text || value.summary || value.reason || value.observation || ""
      if (e.kind === "installation-evidence") description = value.source + " · " + root.dateLabel(value)
      if (e.kind === "snapshot") description = value.subvolume + " · snapshot " + value.number + " (" + value.config + "). Check availability before recovery."
      if (e.kind === "plugin-update") description = value.plugin_id + " · " + (value.success ? "Update command succeeded" : "Update command failed") + "\nRevision: " + (value.before || "unknown").slice(0,12) + " → " + (value.after || "unknown").slice(0,12)
      if (e.kind === "plugin-update-failed") description = value.plugin_id + " · " + value.reason
      if (e.kind === "finished" && value.skipped && value.skipped.length) description += "\nSkipped:\n" + value.skipped.map(function(s) { return (s.plugin_id || s.record) + " · " + s.reason }).join("\n")
      if (e.kind === "command-finished") description = "Command exit code: " + value.exit_code
      if (e.kind === "agent-launched") description = value.action
      return e.at.replace("T", " ").slice(0,19) + " · " + e.kind + (description ? "\n" + description : "")
    }).join("\n\n")
  }
  function finish() {
      if (!exited || !outputDone || !errorsDone) return
      root.working = false
      if (exitCode !== 0) {
        try { root.message = JSON.parse(errors.text).error }
        catch (e) { root.message = "Action failed. Run myomarchy in a terminal for details." }
        drainRefresh()
        return
      }
      try {
        var data = JSON.parse(output.text)
        if (root.request === "refresh" || root.request === "dashboard") {
          root.records = data.records; root.recovery = data.recovery
          root.updating = data.updating === true
          if (root.selected) root.call("show", [root.selected.id], true)
        } else if (root.request === "show") root.selected = data
        else if (root.request === "check-updates") {
          root.message = data.message
          root.call("dashboard", [], true)
        } else if (root.request === "update-plugins") {
          root.message = data.message
          root.updating = data.updating === true
        }
        else if (root.request === "agent") root.message = data.message
        else if (root.request === "baseline") {
          root.detailActive = true
          root.selected = {title: "Configuration comparison", details: "First observed: " + data.captured_at + "\nOriginal installation: unknown\n\n" + data.scope + "\n\nDifferent from current templates:\n" + data.differs_from_templates.join("\n") + "\n\nChanged since first observation:\n" + data.changed_since_observation.join("\n"), events: []}
        } else if (root.request === "recovery") {
          if (Array.isArray(data)) {
            root.detailActive = true
            root.selected = {title: "Existing recovery snapshots", date_kind: "", details: data.map(function(s) { return s.config + " · #" + s.number + " · " + s.date + "\n" + s.description }).join("\n\n"), events: []}
          } else {
            root.recovery = data; root.message = "Recovery configuration updated."
          }
        }
      } catch (e) { root.message = "The helper returned unreadable output." }
      drainRefresh()
  }
  function drainRefresh() {
    if (refreshPending && !working) {
      refreshPending = false
      call("refresh", [], true)
    }
  }
  // Poll only while a user-requested detached update is running.
  Timer {
    interval: 2000; repeat: true; running: root.updating
    onTriggered: if (!root.working) root.call("dashboard", [], true)
  }
  Process {
    id: backend
    stdout: StdioCollector { id: output; waitForEnd: true; onStreamFinished: { root.outputDone = true; root.finish() } }
    stderr: StdioCollector { id: errors; waitForEnd: true; onStreamFinished: { root.errorsDone = true; root.finish() } }
    onExited: function(code) { root.exitCode = code; root.exited = true; root.finish() }
  }
  FloatingWindow {
    id: window
    objectName: "myomarchyWindow"
    visible: root.opened
    title: "My Omarchy"
    implicitWidth: root.preferredSize.width
    implicitHeight: root.preferredSize.height
    minimumSize: Qt.size(360, 300)
    color: root.paper
    onVisibleChanged: if (!visible) root.opened = false
    Shortcut {
      sequence: "Escape"
      enabled: !settings.opened && !moreMenu.opened
      onActivated: if (!root.wideLayout && root.detailActive) root.backToList(); else root.close()
    }
    component Copy: Label {
      color: root.ink
      font.family: Style.font.family
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
    }
    component Action: Button {
      id: action
      enabled: !root.working
      opacity: enabled ? 1 : .45
      contentItem: Text {
        text: action.text; color: root.ink; font.family: Style.font.family
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
      }
      background: Rectangle {
        color: action.hovered ? Qt.lighter(root.paper, 1.6) : root.paper
        border.color: root.ink; border.width: action.activeFocus ? 2 : 1; radius: 3
      }
      padding: 8
    }
    ColumnLayout {
      objectName: "screenSurface"
      anchors.fill: parent; anchors.margins: window.height < 600 ? 12 : 20; spacing: 8
      RowLayout {
        Layout.fillWidth: true
        Copy { Layout.fillWidth: true; text: "MY OMARCHY · " + root.uiVersion; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight; wrapMode: Text.NoWrap }
        Action { text: root.working ? "Working…" : "Refresh"; onClicked: root.call("refresh", []) }
        Action { id: more; text: "More"; onClicked: moreMenu.open() }
        Menu {
          id: moreMenu; x: Math.max(0, more.x + more.width - width); y: more.height
          MenuItem { text: root.recovery.ready ? "Recovery: root + home ready" : "Recovery setup needed"; enabled: false }
          MenuSeparator {}
          MenuItem { text: "Compare configuration"; enabled: !root.working; onTriggered: root.call("baseline", []) }
          MenuItem { text: "Recovery settings"; enabled: !root.working; onTriggered: settings.open() }
          MenuItem { text: "View snapshots"; enabled: !root.working; onTriggered: root.call("recovery", ["list"]) }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        RowLayout {
          visible: window.width >= 600
          Repeater {
            model: [{key:"plugins",name:"Plugins"},{key:"fixes",name:"Fixes"},{key:"customizations",name:"Customizations"},{key:"activity",name:"Activity"}]
            Action {
              required property var modelData
              text: (root.tab === modelData.key ? "● " : "") + modelData.name
              onClicked: { root.tab = modelData.key; root.detailActive = false }
            }
          }
        }
        ComboBox {
          visible: window.width < 600; Layout.fillWidth: true
          model: ["Plugins", "Fixes", "Customizations", "Activity"]
          currentIndex: ["plugins", "fixes", "customizations", "activity"].indexOf(root.tab)
          onActivated: { root.tab = ["plugins", "fixes", "customizations", "activity"][currentIndex]; root.detailActive = false }
        }
        Item { visible: window.width >= 600; Layout.fillWidth: true }
        Copy { visible: window.width >= 900; text: root.recovery.ready ? "Recovery ready" : "Recovery setup needed"; font.pixelSize: 11; opacity: .7 }
      }
      RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; spacing: 16
        ListView {
          id: list
          objectName: "recordList"
          visible: root.wideLayout || !root.detailActive
          Layout.preferredWidth: root.wideLayout ? Math.min(380, window.width * .34) : -1
          Layout.fillWidth: !root.wideLayout; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.minimumWidth: 0
          clip: true; spacing: 4; model: root.visibleRecords()
          focus: true; activeFocusOnTab: true; keyNavigationWraps: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          Keys.onReturnPressed: if (currentItem && !root.working) root.selectRecord(currentItem.modelData.id)
          Keys.onEnterPressed: if (currentItem && !root.working) root.selectRecord(currentItem.modelData.id)
          header: Column {
            width: list.width; spacing: 8; bottomPadding: 8
            TextField {
              width: parent.width; placeholderText: "Filter " + root.tab + "…"; text: root.searchQuery
              onTextEdited: root.searchQuery = text
              color: root.ink; placeholderTextColor: Qt.darker(root.ink, 1.3)
              background: Rectangle { color: root.paper; border.color: root.ink; opacity: .6 }
            }
            Flow {
              width: parent.width; spacing: 6; visible: root.tab === "plugins"
              Action { text: "Check all for updates"; onClicked: root.call("check-updates", []) }
              Action { objectName: "updateAll"; text: root.updating ? "Updating…" : "Update all"; enabled: !root.working && !root.updating; onClicked: root.call("update-plugins", ["--all"]) }
            }
            Copy { width: parent.width; visible: root.tab === "plugins"; text: "Updates need clean GitHub checkouts and recovery points. Local changes are skipped."; font.pixelSize: 11; opacity: .7 }
            CheckBox { text: "Include removed"; checked: root.includeRemoved; onToggled: root.includeRemoved = checked; palette.windowText: root.ink }
          }
          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: list.width; height: rowBody.implicitHeight + 20; radius: 3
            color: root.selected && root.selected.id === modelData.id ? Qt.lighter(root.paper, 1.8) : root.paper
            border.color: list.activeFocus && list.currentIndex === index ? root.ink : Qt.darker(root.ink, 2.5)
            border.width: list.activeFocus && list.currentIndex === index ? 2 : 1
            Column {
              id: rowBody; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10; spacing: 5
              Copy { width: parent.width; text: row.modelData.title; font.bold: true }
              Copy { width: parent.width; text: root.dateLabel(row.modelData, true) + " · " + row.modelData.status; font.pixelSize: 11; opacity: .7 }
              Copy { width: parent.width; visible: row.modelData.category === "plugins"; text: row.modelData.update_status || "Not checked"; font.pixelSize: 11 }
            }
            MouseArea { anchors.fill: parent; enabled: !root.working; onClicked: { list.currentIndex = row.index; root.selectRecord(row.modelData.id) } }
          }
          footer: Copy {
            objectName: "emptyRecords"
            width: list.width; topPadding: 12; bottomPadding: 12
            visible: list.count === 0; height: visible ? implicitHeight : 0
            text: "No matching records."
          }
        }
        ColumnLayout {
          visible: root.wideLayout || root.detailActive
          Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.minimumWidth: 0; spacing: 6
          Action { id: backAction; objectName: "backToList"; visible: !root.wideLayout; text: "← Back to " + root.tab; onClicked: root.backToList() }
          ScrollView {
            id: detailScroll
            objectName: "detailScroll"
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0; Layout.minimumWidth: 0
            clip: true; contentWidth: availableWidth; contentHeight: detailBody.implicitHeight
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ColumnLayout {
              id: detailBody
              width: detailScroll.availableWidth; spacing: 10
              Copy { Layout.fillWidth: true; text: root.selected ? root.selected.title : "Select a change"; font.pixelSize: 20; font.bold: true }
              Copy { Layout.fillWidth: true; visible: !!root.selected; text: root.selected ? root.dateLabel(root.selected) : "" }
              Copy {
                Layout.fillWidth: true; opacity: .75
                text: root.selected && root.selected.origin === "journal" ? "Reconstructed history. Current state and recovery need verification."
                  : root.selected && root.selected.origin === "discovered" ? (root.selected.date_kind === "inferred-install" ? "Installation estimated from the local clone log and location creation time."
                    : root.selected.date_kind === "installed" ? "Installation linked to a verified managed change."
                    : root.selected.date_kind === "location-created" ? "Location creation is known; the exact installation time is unconfirmed."
                    : "Known present by the first recorded observation; exact installation time is unavailable.") : "Details stay local until you discuss them with your agent."
              }
              Copy {
                visible: !!(root.selected && root.selected.category === "plugins")
                Layout.fillWidth: true; font.pixelSize: 12
                text: root.selected ? (root.selected.update_status || "Not checked") + (root.selected.checked_at ? " · Checked " + new Date(root.selected.checked_at).toLocaleString() : "") : ""
              }
              Flow {
                visible: !!(root.selected && root.selected.category === "plugins" && root.selected.status === "present")
                Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 6
                Action { text: "Check for updates"; onClicked: root.call("check-updates", [root.selected.id]) }
                Action { objectName: "updatePlugin"; text: "Update plugin"; enabled: !root.working && !root.updating && !!(root.selected && root.selected.can_update); onClicked: root.call("update-plugins", ["--id", root.selected.id]) }
                Action { text: "GitHub repository"; enabled: !root.working && !!(root.selected && root.selected.repository); onClicked: Qt.openUrlExternally(root.selected.repository) }
                Action { text: "Ask agent about updating"; onClicked: root.call("agent", [root.selected.id,"update-advice"]) }
              }
              Copy { visible: !!(root.selected && root.selected.update_blocked_reason); Layout.fillWidth: true; font.pixelSize: 11; text: root.selected ? root.selected.update_blocked_reason || "" : "" }
              TextArea {
                objectName: "recordDetails"
                Layout.fillWidth: true; Layout.preferredHeight: contentHeight + topPadding + bottomPadding
                text: root.detailsText(root.selected)
                readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: root.ink
                textFormat: TextEdit.PlainText; font.family: Style.font.family; font.pixelSize: 13
                background: Rectangle { color: root.paper }
              }
              Flow {
                Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 6
                Action { text: "Discuss"; visible: !!(root.selected && root.selected.id); onClicked: root.call("agent", [root.selected.id,"discuss"]) }
                Action { text: "Investigate a problem"; visible: !!(root.selected && root.selected.id); onClicked: root.call("agent", [root.selected.id,"investigate"]) }
                Action { text: "Uninstall"; visible: !!(root.selected && root.selected.category === "plugins" && root.selected.status === "present"); onClicked: root.call("agent", [root.selected.id,"uninstall"]) }
              }
              Copy { Layout.fillWidth: true; font.pixelSize: 11; opacity: .65; text: "Agent actions open your default agent and may send retrieved details to its provider. Uninstall authorizes ordinary removal; shared data or dependencies need approval." }
            }
          }
        }
      }
      ScrollView {
        visible: root.message !== ""
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(64, messageText.implicitHeight)
        contentWidth: availableWidth; clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Copy { id: messageText; width: parent.width; text: root.message; font.pixelSize: 12 }
      }
    }
    Dialog {
      id: settings
      objectName: "recoveryDialog"
      title: "Recovery settings"; anchors.centerIn: parent; modal: true
      width: Math.min(560, window.width - 24); height: Math.min(500, window.height - 24)
      background: Rectangle { color: root.paper; border.color: root.ink }
      contentItem: ScrollView {
        id: recoveryScroll
        clip: true; contentWidth: availableWidth; contentHeight: recoveryBody.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
          id: recoveryBody; width: recoveryScroll.availableWidth; spacing: 10
          Copy { Layout.fillWidth: true; text: "Creates missing root/home Snapper configurations with five retained snapshots. Existing policies are preserved unless you choose to change them. Nothing is restored automatically." }
          CheckBox { id: changeRetention; text: "Change existing retention"; checked: false; palette.windowText: root.ink }
          Copy { Layout.fillWidth: true; text: "Changing retention also affects Omarchy update snapshots."; font.pixelSize: 11 }
          RowLayout { Copy { text: "Keep per area" } SpinBox { id: keep; from: 2; to: 1000; value: 5; editable: true; enabled: changeRetention.checked } }
          Copy { Layout.fillWidth: true; text: "Space target per area (%) · 0 keeps current policy" }
          SpinBox { id: space; from: 0; to: 50; value: 0; editable: true }
          Copy { Layout.fillWidth: true; text: "Space targets enable Btrfs quotas. Root and home share disk space; cleanup targets are not a hard total cap. Full home restoration rewinds personal files. Nested subvolumes and other mounts are excluded." }
        }
      }
      footer: DialogButtonBox {
        Button { text: "Cancel"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        Button { text: "Apply settings"; enabled: !root.working; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
      }
      onRejected: close()
      onAccepted: {
        var args = ["setup"]
        if (changeRetention.checked) args = args.concat(["--keep", String(keep.value)])
        if (space.value > 0) args = args.concat(["--space-fraction", String(space.value/100)])
        close(); root.call("recovery", args)
      }
    }
  }
}
