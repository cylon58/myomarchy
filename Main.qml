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
  property bool opened: false
  property string helper: decodeURIComponent(Qt.resolvedUrl("bin/myomarchy").toString().replace("file://", ""))
  property var records: []
  property var selected: null
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
        && (showRemoved.checked || r.status !== "removed")
        && (!search.text || r.title.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
    })
  }
  function dateLabel(r) {
    if (!r.date) return "Install date unknown"
    var date = r.date.indexOf("T") >= 0 ? new Date(r.date).toLocaleString() : r.date
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
          root.selected = {title: "Configuration comparison", details: "First observed: " + data.captured_at + "\nOriginal installation: unknown\n\n" + data.scope + "\n\nDifferent from current templates:\n" + data.differs_from_templates.join("\n") + "\n\nChanged since first observation:\n" + data.changed_since_observation.join("\n"), events: []}
        } else if (root.request === "recovery") {
          if (Array.isArray(data)) {
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
    implicitWidth: 1120
    implicitHeight: 740
    minimumSize: Qt.size(840, 580)
    color: root.paper
    onVisibleChanged: if (!visible) root.opened = false
    Shortcut { sequence: "Escape"; onActivated: root.close() }
    component Copy: Label {
      color: root.ink
      font.family: Style.font.family
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
    }
    component Action: Button {
      id: action
      enabled: !root.working
      contentItem: Text {
        text: action.text; color: root.ink; font.family: Style.font.family
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
      }
      background: Rectangle { color: action.hovered ? Qt.lighter(root.paper, 1.6) : root.paper; border.color: root.ink; opacity: action.enabled ? 1 : .4; radius: 3 }
      padding: 10
    }
    ColumnLayout {
      objectName: "screenSurface"
      anchors.fill: parent; anchors.margins: 24; spacing: 14
      RowLayout {
        ColumnLayout {
          Copy { text: "MY OMARCHY"; font.pixelSize: 26; font.bold: true }
          Copy { text: "Your machine. Your changes. A history you can ask about."; opacity: .75 }
        }
        Item { Layout.fillWidth: true }
        Action { text: "Compare configuration"; onClicked: root.call("baseline", []) }
        Action { text: root.working ? "Working…" : "Refresh history"; onClicked: root.call("refresh", []) }
      }
      Rectangle { Layout.fillWidth: true; height: 1; color: root.ink; opacity: .3 }
      RowLayout {
        Layout.fillWidth: true
        Copy {
          Layout.fillWidth: true
          text: root.recovery.ready ? "Recovery: root + home configured. Creation is checked before each managed change."
            : "Recovery setup needed: " + (root.recovery.missing || []).join(", ") + ". Managed changes will wait."
        }
        Action { text: "Recovery settings"; onClicked: settings.open() }
        Action { text: "View snapshots"; onClicked: root.call("recovery", ["list"]) }
      }
      RowLayout {
        Repeater {
          model: [{key:"plugins",name:"Plugins"},{key:"fixes",name:"Fixes"},{key:"customizations",name:"Customizations"},{key:"activity",name:"Activity"}]
          Action {
            required property var modelData
            text: (root.tab === modelData.key ? "● " : "") + modelData.name
            onClicked: root.tab = modelData.key
          }
        }
        Item { Layout.fillWidth: true }
        CheckBox { id: showRemoved; text: "Include removed"; palette.windowText: root.ink }
      }
      RowLayout {
        visible: root.tab === "plugins"
        Layout.fillWidth: true
        Action { text: "Check all for updates"; onClicked: root.call("check-updates", []) }
        Action { text: root.updating ? "Updating…" : "Update all"; enabled: !root.working && !root.updating; onClicked: root.call("update-plugins", ["--all"]) }
        Copy { Layout.fillWidth: true; font.pixelSize: 11; text: "Updates require clean GitHub checkouts and recovery points. Local changes are skipped." }
      }
      TextField {
        id: search; Layout.fillWidth: true; placeholderText: "Filter this tab by name or summary…"
        color: root.ink; placeholderTextColor: Qt.darker(root.ink,1.3)
        background: Rectangle { color: root.paper; border.color: root.ink; opacity: .6 }
      }
      RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 20
        ListView {
          id: list; Layout.preferredWidth: window.width * .45; Layout.fillHeight: true
          clip: true; spacing: 4; model: root.visibleRecords()
          ScrollBar.vertical: ScrollBar {}
          delegate: Rectangle {
            id: row
            required property var modelData
            width: list.width; height: row.modelData.category === "plugins" ? 86 : 66; radius: 3
            color: root.selected && root.selected.id === modelData.id ? Qt.lighter(root.paper, 1.8) : root.paper
            border.color: Qt.darker(root.ink, 2.5)
            Column {
              anchors.fill: parent; anchors.margins: 10; spacing: 5
              Copy { width: parent.width; text: row.modelData.title; wrapMode: Text.NoWrap; elide: Text.ElideRight; font.bold: true }
              Copy { width: parent.width; text: root.dateLabel(row.modelData) + " · " + row.modelData.status; font.pixelSize: 11; wrapMode: Text.NoWrap; elide: Text.ElideRight; opacity: .7 }
              Copy { width: parent.width; visible: row.modelData.category === "plugins"; text: row.modelData.update_status || "Not checked"; font.pixelSize: 11; elide: Text.ElideRight }
            }
            MouseArea { anchors.fill: parent; enabled: !root.working; onClicked: root.call("show", [row.modelData.id]) }
          }
          Copy { anchors.centerIn: parent; visible: list.count === 0; text: "No matching records." }
        }
        ColumnLayout {
          Layout.fillWidth: true; Layout.fillHeight: true
          Copy { Layout.fillWidth: true; text: root.selected ? root.selected.title : "Select a change"; font.pixelSize: 20; font.bold: true }
          Copy {
            Layout.fillWidth: true; opacity: .75
            text: root.selected && root.selected.origin === "journal" ? "Reconstructed from your journal. Current state and recovery instructions need verification."
              : root.selected && root.selected.origin === "discovered" ? "Observed on this machine. Original install time is unknown." : "Details remain local until you choose to discuss them with your agent."
          }
          Copy {
            visible: !!(root.selected && root.selected.category === "plugins")
            Layout.fillWidth: true; font.pixelSize: 12
            text: root.selected ? (root.selected.update_status || "Not checked") + (root.selected.checked_at ? " · Checked " + new Date(root.selected.checked_at).toLocaleString() : "") : ""
          }
          Flow {
            visible: !!(root.selected && root.selected.category === "plugins" && root.selected.status === "present")
            Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 8
            Action { text: "GitHub repository"; enabled: !root.working && !!(root.selected && root.selected.repository); onClicked: Qt.openUrlExternally(root.selected.repository) }
            Action { text: "Check for updates"; onClicked: root.call("check-updates", [root.selected.id]) }
            Action { text: "Update plugin"; enabled: !root.working && !root.updating && !!(root.selected && root.selected.can_update); onClicked: root.call("update-plugins", ["--id", root.selected.id]) }
            Action { text: "Ask agent about updating"; onClicked: root.call("agent", [root.selected.id,"update-advice"]) }
          }
          Copy {
            visible: !!(root.selected && root.selected.category === "plugins" && root.selected.update_blocked_reason)
            Layout.fillWidth: true; font.pixelSize: 11; opacity: .7
            text: root.selected ? root.selected.update_blocked_reason || "" : ""
          }
          ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            TextArea {
              text: root.detailsText(root.selected)
              readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: root.ink
              textFormat: TextEdit.PlainText; font.family: Style.font.family; font.pixelSize: 13
              background: Rectangle { color: root.paper }
            }
          }
          Flow {
            Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 8
            Action { text: "Discuss"; visible: !!(root.selected && root.selected.id); onClicked: root.call("agent", [root.selected.id,"discuss"]) }
            Action { text: "Investigate a problem"; visible: !!(root.selected && root.selected.id); onClicked: root.call("agent", [root.selected.id,"investigate"]) }
            Action { text: "Uninstall"; visible: !!(root.selected && root.selected.category === "plugins" && root.selected.status === "present"); onClicked: root.call("agent", [root.selected.id,"uninstall"]) }
          }
          Copy { Layout.fillWidth: true; font.pixelSize: 11; opacity: .65; text: "Agent actions open your default agent. It may send retrieved record details to its provider. Uninstall authorizes ordinary removal; shared data or dependency changes need your approval." }
        }
      }
      Copy { Layout.fillWidth: true; visible: root.message !== ""; text: root.message; maximumLineCount: 3; elide: Text.ElideRight }
      Copy { Layout.fillWidth: true; opacity: .6; font.pixelSize: 11; text: "PILOT · Original installation baseline unknown · Outside changes may have incomplete history · Snapshots can expire; the journal remains." }
    }
    Dialog {
      id: settings; title: "Recovery settings"; anchors.centerIn: parent; modal: true; width: 560
      background: Rectangle { color: root.paper; border.color: root.ink }
      contentItem: ColumnLayout {
        Copy { Layout.fillWidth: true; text: "Creates missing root/home Snapper configurations with five retained snapshots. Existing policies are preserved unless you choose to change them. Nothing is restored automatically." }
        CheckBox { id: changeRetention; text: "Change existing retention (including Omarchy update snapshots)"; checked: false }
        RowLayout { Copy { text: "Keep per area" } SpinBox { id: keep; from: 2; to: 1000; value: 5; editable: true; enabled: changeRetention.checked } }
        RowLayout { Copy { text: "Space target per area (%) · 0 keeps existing policy" } SpinBox { id: space; from: 0; to: 50; value: 0; editable: true } }
        Copy { Layout.fillWidth: true; text: "A space target enables Btrfs quota accounting. Root and home share disk space; these are cleanup targets, not a hard total cap. Full home restoration would rewind personal files. Nested subvolumes and other mounts are excluded." }
        Action { text: "Apply with administrator approval"; onClicked: { var args = ["setup"]; if(changeRetention.checked) args = args.concat(["--keep",String(keep.value)]); if(space.value > 0) args = args.concat(["--space-fraction",String(space.value/100)]); settings.close(); root.call("recovery",args) } }
      }
    }
  }
}
