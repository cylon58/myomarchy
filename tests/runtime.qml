import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: test
  property int step: 0
  property int ticks: 0
  Plugin.Main {
    id: app
    helper: Quickshell.env("MYOMARCHY_TEST_HELPER")
    Component.onCompleted: open()
  }
  function check(value, message) {
    if (!value) { console.error("TEST_FAILED: " + message); Qt.quit() }
    return value
  }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: {
      test.ticks++
      if (test.ticks > 100) { console.error("TEST_FAILED: timeout"); Qt.quit(); return }
      if (app.working) return
      if (test.step === 0) {
        if (!test.check(app.records.length === 2, "loaded real Process JSON")) return
        if (!test.check(app.visibleRecords().length === 1, "plugins filter")) return
        app.tab = "fixes"
        if (!test.check(app.visibleRecords()[0].id === "demo-fix", "fixes tab")) return
        app.tab = "activity"
        if (!test.check(app.visibleRecords().length === 2, "activity includes history")) return
        app.tab = "plugins"; app.call("show", ["demo-plugin"]); test.step++
      } else if (test.step === 1) {
        if (!test.check(app.selected && app.selected.id === "demo-plugin", "detail loaded")) return
        app.call("agent", ["demo-plugin", "investigate"]); test.step++
      } else if (test.step === 2) {
        if (!test.check(app.message === "TEST: investigate", "agent action dispatch")) return
        app.close()
        app.call("show", ["demo-plugin"])
        app.open()
        if (!test.check(app.refreshPending, "opening while busy queues refresh")) return
        test.step++
      } else if (test.step === 3) {
        if (!test.check(!app.refreshPending && app.opened, "queued opening refresh completes")) return
        app.call("bad-action", []); test.step++
      } else if (test.step === 4) {
        if (!test.check(app.message === "Test error", "errors visible")) return
        app.close()
        app.call("bad-action", [])
        app.open()
        test.step++
      } else if (test.step === 5) {
        if (!test.check(app.message === "Test error", "reopening preserves action errors")) return
        if (!test.check(app.selected.repository === "https://github.com/example/plugin", "repository metadata loads")) return
        app.call("agent", ["demo-plugin", "update-advice"])
        test.step++
      } else if (test.step === 6) {
        if (!test.check(app.message === "TEST: update-advice", "update advice dispatch")) return
        app.message = "Preview uses synthetic records."
        test.step++
        for (var i=0; i<app.resources.length; i++) {
          var resource = app.resources[i]
          if (resource.objectName === "myomarchyWindow") {
            var surface = null
            for (var j=0; j<resource.contentItem.children.length; j++) {
              if (resource.contentItem.children[j].objectName === "screenSurface") surface = resource.contentItem.children[j]
            }
            if (!surface) { console.error("TEST_FAILED: surface missing"); Qt.quit(); return }
            surface.grabToImage(function(result) {
              result.saveToFile(Quickshell.env("MYOMARCHY_TEST_IMAGE"))
              console.log("PILOT_QML_PASSED"); Qt.quit()
            }); return
          }
        }
        console.error("TEST_FAILED: window missing"); Qt.quit()
      }
    }
  }
}
