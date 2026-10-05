import QtQuick
import QtTest
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: test
  property int ticks: 0
  property int step: 0
  property int sizeIndex: 0
  property var sizes: [[Number(Quickshell.env("MYOMARCHY_TEST_WIDTH")), Number(Quickshell.env("MYOMARCHY_TEST_HEIGHT"))]]
  property var window: null
  property var savedScroll: 0
  property real wheelStart: 0
  TestCase { id: input; name: "NativeScrollInput"; when: false }
  Plugin.Main { id: app; preferredSize: Qt.size(test.sizes[0][0], test.sizes[0][1]); helper: Quickshell.env("MYOMARCHY_TEST_HELPER"); Component.onCompleted: open() }
  function find(object, name, visited) {
    if (!object || visited.indexOf(object) >= 0) return null
    visited.push(object)
    if (object.objectName === name) return object
    var groups = [object.children || [], object.resources || [], object.data || []]
    for (var g=0; g<groups.length; g++) for (var i=0; i<groups[g].length; i++) {
      var result = find(groups[g][i], name, visited)
      if (result) return result
    }
    return null
  }
  function check(value, reason) { if (!value) { console.error("RESPONSIVE_FAILED: " + reason); Qt.quit() }; return value }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: {
      if (++test.ticks > 120) { console.error("RESPONSIVE_FAILED: timeout"); Qt.quit(); return }
      if (app.working) return
      if (test.step === 0) {
        test.window = test.find(app, "myomarchyWindow", [])
        if (!test.check(!!test.window, "window found")) return
        app.selectRecord("demo-plugin"); test.step++; return
      }
      if (test.step === 1) {
        var details = []
        for (var n=0; n<80; n++) details.push("Long history line " + n + ": record detail remains readable and selectable.")
        app.selected = Object.assign({}, app.selected, {details: details.join("\n")})
        var records = []
        for (var j=0; j<30; j++) records.push(Object.assign({}, app.records[0], {id:"fixture-"+j}))
        app.records = records
        test.step++; return
      }
      if (test.step === 2) {
        var size = test.sizes[test.sizeIndex]
        app.detailActive = true; test.step++; return
      }
      var list = test.find(test.window.contentItem, "recordList", [])
      var detail = test.find(test.window.contentItem, "detailScroll", [])
      var update = test.find(test.window.contentItem, "updatePlugin", [])
      if (test.step === 3) {
        var currentSize = test.sizes[test.sizeIndex]
        if (!test.check(test.window.width === currentSize[0] && test.window.height === currentSize[1], "requested native size: " + test.window.width + "," + test.window.height)) return
        if (!test.check(detail.visible && detail.availableHeight >= 120 && detail.availableWidth >= 280, "usable detail viewport at " + currentSize)) return
        if (!test.check(list.visible === (currentSize[0] >= 900), "responsive pane visibility")) return
        if (!test.check(update.visible && update.width <= detail.availableWidth, "update action fits")) return
        if (!test.check(detail.contentWidth <= detail.availableWidth + 1, "no horizontal detail overflow")) return
        if (!test.check(detail.contentHeight > detail.availableHeight, "whole detail pane scrolls")) return
        detail.contentItem.contentY = Math.max(0, update.mapToItem(detail, 0, 0).y - 30)
        test.wheelStart = detail.contentItem.contentY
        input.mouseWheel(update, 10, 10, 0, -120, Qt.NoButton, Qt.NoModifier, 0)
        test.step = 31; return
      }
      if (test.step === 31) {
        if (!test.check(detail.contentItem.contentY > test.wheelStart, "wheel over action scrolls whole details")) return
        var text = test.find(test.window.contentItem, "recordDetails", [])
        detail.contentItem.contentY += text.mapToItem(detail, 0, 0).y - 30
        test.wheelStart = detail.contentItem.contentY
        input.mouseWheel(text, 10, 10, 0, -120, Qt.NoButton, Qt.NoModifier, 0)
        test.step = 32; return
      }
      if (test.step === 32) {
        if (!test.check(detail.contentItem.contentY > test.wheelStart, "wheel over text scrolls whole details")) return
        detail.contentItem.contentY = detail.contentHeight - detail.availableHeight
        test.step = 4; return
      }
      if (test.step === 4) {
        if (!test.check(detail.contentItem.contentY > 0, "detail scroll reaches long history")) return
        var recovery = test.find(test.window, "recoveryDialog", [])
        if (!test.check(!!recovery, "recovery dialog found")) return
        app.selected = Object.assign({}, app.selected, {id: "new-record-" + test.sizeIndex})
        recovery.open(); test.step++; return
      }
      if (test.step === 5) {
        if (!test.check(detail.contentItem.contentY === 0, "new record opens at its title and update controls")) return
        var recoveryDialog = test.find(test.window, "recoveryDialog", [])
        if (!test.check(recoveryDialog.width <= test.window.width - 20 && recoveryDialog.height <= test.window.height - 20, "recovery dialog fits")) return
        recoveryDialog.close()
        if (!app.wideLayout) {
          app.detailActive = false
          list.contentY = 500
          test.savedScroll = list.contentY
          test.step++; return
        }
        test.step = 7; return
      }
      if (test.step === 6) {
        if (!test.check(list.visible && list.contentY >= 490 && !!app.selected, "Back retains selection and list position")) return
        list.forceActiveFocus()
        list.currentIndex = 0
        input.keyClick(Qt.Key_Down, Qt.NoModifier, 0)
        input.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
        test.step = 61; return
      }
      if (test.step === 61) {
        if (!test.check(app.detailActive && !!app.selected, "arrow and Enter open a record")) return
        input.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
        test.step = 62; return
      }
      if (test.step === 62) {
        if (!test.check(!app.detailActive && app.opened, "Escape returns to list")) return
        app.searchQuery = "no-match-at-all"
        test.step = 63; return
      }
      if (test.step === 63) {
        var empty = test.find(test.window.contentItem, "emptyRecords", [])
        if (!test.check(list.count === 0 && empty.visible && empty.mapToItem(list.contentItem, 0, 0).y >= list.headerItem.mapToItem(list.contentItem, 0, 0).y + list.headerItem.height - 1, "empty state follows list controls: count=" + list.count + " visible=" + empty.visible + " y=" + empty.mapToItem(list.contentItem, 0, 0).y + " header=" + list.headerItem.height + " scroll=" + list.contentY)) return
        app.searchQuery = ""; app.detailActive = true
        test.step = 7; return
      }
      if (test.step === 7) {
        console.log("RESPONSIVE_SIZE_PASSED: " + test.sizes[test.sizeIndex])
        if (++test.sizeIndex < test.sizes.length) { test.step = 2; return }
        console.log("RESPONSIVE_QML_PASSED"); Qt.quit()
      }
    }
  }
}
