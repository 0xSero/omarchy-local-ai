import QtQuick
import Quickshell
import QtTest
import "../ui" as Local

// Run with test/navigation on an Omarchy host; all controller calls use a fixture.
ShellRoot {
  PanelWindow {
    visible: true; implicitWidth: 700; implicitHeight: 650
    Item {
      id: viewport
      width: 360; height: 400; clip: true
      Flickable {
        id: outer
        anchors.fill: parent; contentWidth: width; contentHeight: subject.y + subject.height
        clip: true; visible: subject.embedded; interactive: visible && contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        function scroll(amount) { contentY = Math.max(0, Math.min(Math.max(0, contentHeight-height), contentY+amount)) }
        onContentHeightChanged: scroll(0)
        onHeightChanged: scroll(0)
      }
      Local.Panel {
        id: subject
        width: viewport.width
        parent: embedded ? outer.contentItem : viewport
        y: embedded ? 100 : 0
        height: embedded ? implicitHeight : 0
        overlayHost: viewport
        onRevealRequested: function(y, rowHeight) {
          var top = subject.y + y
          if (top < outer.contentY) outer.contentY = Math.max(0, top)
          else if (top + rowHeight > outer.contentY + outer.height)
            outer.contentY = Math.min(Math.max(0, outer.contentHeight-outer.height), top+rowHeight-outer.height)
        }
      }
    }
    TestCase {
      id: test
      name: "Navigation"
      when: true
      property var fixtureData
      function assertUi(condition, message) {
        if (!condition) console.log("NAV_FAIL",message,subject.embedded,viewport.width,viewport.height,subject.view)
        verify(condition,message)
      }
      function same(actual, expected) {
        if (actual !== expected) console.log("NAV_FAIL compare",actual,expected,subject.embedded,subject.view)
        compare(actual,expected)
      }
      function initTestCase() { wait(350); fixtureData = JSON.parse(JSON.stringify(subject.snap)); same(fixtureData.state, "ready") }
      function init() {
        subject.snap = JSON.parse(JSON.stringify(fixtureData)); subject.pending = false
        subject.launcherOpen = false; subject.agentOpen = false; subject.activate("home")
      }
      function setup(mode, w, h, view) {
        subject.embedded = mode; subject.contentFocus.parent = mode ? subject : viewport
        viewport.width = w; viewport.height = h
        if (view === "home") { subject.launcherOpen = true; subject.agentOpen = true }
        else if (view === "empty") subject.snap = Object.assign({},fixtureData,{state:"idle",models:[],cards:[],recipes:[]})
        else if (view === "error") subject.snap = Object.assign({},fixtureData,{state:"error",error:"Fixture deployment failed"})
        else if (view === "work") subject.snap = Object.assign({},fixtureData,{state:"starting",operation:{recipeId:"test-model",detail:"starting",percent:20}})
        else if (view === "folder") { subject.launcherOpen = true; subject.editFolder() }
        else subject.activate(view === "card" ? "card:test-gpu" : "model:test-model")
        wait(80); subject.scrollBy(-1e9); wait(30)
        return mode ? outer : findChild(subject.contentFocus, "local-ai-scroll")
      }
      function test_scroll_data() {
        var out = []
        for (var mode of [false,true]) for (var size of [[240,180],[380,400],[600,650]]) for (var view of ["home","card","model","folder","empty","error","work"])
          out.push({tag:mode+"-"+size.join("x")+"-"+view, mode:mode,w:size[0],h:size[1],view:view})
        return out
      }
      function test_scroll(d) {
        var f = setup(d.mode,d.w,d.h,d.view), max = Math.max(0,f.contentHeight-f.height)
        // Real wheel events over the top of the page, including header/editor areas.
        mouseWheel(viewport,Math.min(90,d.w/2),15,0,-120); wait(100)
        if (max > 1) assertUi(f.contentY > 0, "wheel must reach the page viewport")
        subject.scrollBy(-1e9); mouseWheel(viewport,d.w/2,d.h*.6,0,-120); wait(100)
        if (max > 1) assertUi(f.contentY > 0, "wheel over controls reaches the viewport")
        subject.editingFolder = false; subject.focusContent(); wait(30)
        keyClick(Qt.Key_End); wait(30)
        assertUi(Math.abs(f.contentY-Math.max(0,f.contentHeight-f.height)) < 1, "End reaches bottom actions")
        keyClick(Qt.Key_Home); wait(30); assertUi(f.contentY < 1)
        keyClick(Qt.Key_PageDown); wait(30)
        if (f.contentHeight>f.height+1) assertUi(f.contentY>0, "PageDown")
        subject.cursor = subject.actionable.length-1; wait(40)
        var selected = subject.cursorAt
        var footer = findChild(subject.contentFocus,selected < subject.ui.rows.length ? "content-row-"+selected : "footer-row-"+(selected-subject.ui.rows.length))
        if (selected >= 0) {
          assertUi(footer !== null,"selected action exists")
          var pos = footer.mapToItem(viewport,0,0)
          assertUi(pos.y >= -1 && pos.y+footer.height <= viewport.height+1, "keyboard reveals selected action: " + pos.y + ", " + footer.height)
        }
        viewport.height += 60; wait(30)
        assertUi(f.contentY <= Math.max(0,f.contentHeight-f.height)+1, "resize clamps position")
        subject.activate("home"); wait(50); assertUi(f.contentY<1, "view navigation resets scroll")
        console.log("NAV_PASS",d.tag)
      }
      function clickCrumb(index) {
        var link = findChild(subject.contentFocus,"breadcrumb-"+index); assertUi(link !== null, "breadcrumb exists: " + index + " path=" + JSON.stringify(subject.ui.path) + " models=" + subject.snap.models.length)
        subject.revealItem(link); wait(30); mouseClick(link,link.width/2,link.height/2); wait(50)
      }
      function test_breadcrumbs_data() { return [{tag:"standalone",mode:false},{tag:"embedded",mode:true}] }
      function test_breadcrumbs(d) {
        setup(d.mode,240,180,"model")
        clickCrumb(2); same(subject.view,"model")
        clickCrumb(1); same(subject.view,"card"); same(subject.hw,"test-gpu")
        subject.activate("count:2"); wait(30)
        clickCrumb(2); same(subject.count,2)
        clickCrumb(1); same(subject.count,1)
        clickCrumb(0); same(subject.view,"home")
        // The current progress breadcrumb and its ancestors also navigate.
        subject.snap = Object.assign({},fixtureData,{state:"starting",operation:{recipeId:"test-model",detail:"starting",percent:20}})
        wait(30); assertUi(subject.working,"operation remains working")
        clickCrumb(subject.ui.path.length-1); same(subject.ui.path.slice(-1)[0].v,"work")
        clickCrumb(1); same(subject.view,"card"); assertUi(subject.browseWhileWorking,"can browse while working")
        assertUi(subject.ui.foot.every(function(r) { return !r.action || r.disabled }),"conflicting actions disabled")
        subject.activate("work"); wait(30); assertUi(!subject.browseWhileWorking,"return to work")
        clickCrumb(0); same(subject.view,"home"); assertUi(subject.browseWhileWorking,"can browse while working")
        console.log("CRUMB_PASS",d.tag)
      }
      function cleanupTestCase() { console.log("NAV_DONE"); Qt.quit() }
    }
  }
}
