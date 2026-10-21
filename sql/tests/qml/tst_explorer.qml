import QtQuick
import QtTest
import Logos.Theme
import "../../src/qml"

Rectangle {
    id: scene
    width: 1200
    height: 850
    color: Theme.palette.background

    QtObject {
        id: backend
        property bool connected: true
        property bool busy: false
        property string nodeUrl: "http://localhost:8080"
        property string channelId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        property var recentConnections: [
            {nodeUrl: "http://localhost:8081", channelId: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
            {nodeUrl: "http://localhost:8080", channelId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
        ]
        property string readView: "latest"
        property var tables: [{name: "reviews", type: "table", sql: "CREATE TABLE reviews (id INTEGER PRIMARY KEY, review TEXT)"}]
        property int returnedRows: 0
        property bool truncated: false
        property int calls: 0
        property int offset: -1
        property var browseReply: ({success: true})
        function browseTable(name, rowOffset, limit) { calls++; offset = rowOffset; return browseReply }
        function runQuery(sql, limit) { calls++; return {success: true} }
        function openChannel(url, channel) { calls++; return {success: true} }
        function refreshSchema(view) { calls++; readView = view; return {success: true} }
    }

    Explorer {
        id: explorer
        anchors.fill: parent
        anchors.margins: 20
        backend: backend
        resultModel: testResults
        watch: function(reply, completed, failed) { completed(reply) }
    }

    TestCase {
        name: "Explorer"
        when: windowShown

        function init() {
            backend.calls = 0
            backend.busy = false
            backend.connected = true
            backend.truncated = false
            backend.offset = -1
            backend.browseReply = {success: true}
            explorer.ready = false
            explorer.ready = true
            explorer.watch = function(reply, completed, failed) { completed(reply) }
        }

        function test_restoresConnectionFields() {
            compare(findChild(explorer, "nodeUrl").text, backend.nodeUrl)
            compare(findChild(explorer, "channelId").text, backend.channelId)
        }

        function test_selectsPreviousConnection() {
            const recent = findChild(explorer, "recentConnections")
            compare(recent.count, 2)
            recent.currentIndex = 0
            recent.activated(0)
            compare(findChild(explorer, "nodeUrl").text, backend.recentConnections[0].nodeUrl)
            compare(findChild(explorer, "channelId").text, backend.recentConnections[0].channelId)
            compare(backend.calls, 0)

            // Selecting fills the fields; opening remains an explicit action.
            let finish
            explorer.watch = function(reply, completed, failed) { finish = completed }
            findChild(explorer, "openChannel").clicked()
            compare(recent.enabled, false)
            finish({success: true})
            compare(recent.enabled, true)
        }

        function test_channelStatusWhileOpening() {
            backend.connected = false
            const status = findChild(explorer, "connectionStatus")
            compare(status.text, "No channel open")

            let finish
            explorer.watch = function(reply, completed, failed) { finish = completed }
            findChild(explorer, "openChannel").clicked()
            compare(status.text, "Syncing channel…")

            finish({success: false, error: "Connection timed out"})
            compare(status.text, "No channel open")

            findChild(explorer, "openChannel").clicked()
            backend.connected = true
            finish({success: true})
            compare(status.text, "Read-only replica open")
        }

        function test_preventsOverlappingRequests() {
            let finish
            explorer.watch = function(reply, completed, failed) { finish = completed }
            explorer.invoke(function() { return backend.runQuery("SELECT 1", 200) })
            compare(explorer.working, true)
            explorer.invoke(function() { return backend.runQuery("SELECT 2", 200) })
            compare(backend.calls, 1)
            finish({success: false, error: "read-only query required"})
            compare(explorer.working, false)
            compare(findChild(explorer, "errorMessage").text, "read-only query required")
        }

        function test_switchesReadView() {
            let selector = findChild(explorer, "readView")
            selector.currentIndex = 1
            selector.activated(1)
            compare(backend.readView, "finalized")
            compare(backend.calls, 1)
        }

        function test_backendDisconnectClearsSelection() {
            explorer.browse(0, backend.tables[0])
            compare(findChild(explorer, "tableSchema").text, backend.tables[0].sql)
            explorer.ready = false
            compare(findChild(explorer, "tableSchema").text, "")
            compare(findChild(explorer, "nextPage").visible, false)
            compare(findChild(explorer, "openChannel").enabled, false)
        }

        function test_rendersResults() {
            backend.returnedRows = 1
            waitForRendering(explorer)
            let grid = findChild(explorer, "resultGrid")
            tryCompare(grid, "rows", 1)
            tryCompare(grid, "columns", 3)
            tryVerify(function() { return grid.itemAtCell(Qt.point(0, 0)) !== null })
            compare(grid.itemAtCell(Qt.point(0, 0)).display, "9223372036854775807")
            compare(grid.itemAtCell(Qt.point(2, 0)).display, "NULL")
            if (previewPath.length) grabImage(scene).save(previewPath)
        }

        function test_pagingOnlyAdvancesAfterSuccess() {
            explorer.browse(0, backend.tables[0])
            let next = findChild(explorer, "nextPage")
            const summary = findChild(explorer, "resultSummary")
            compare(next.enabled, false)
            backend.truncated = true
            compare(next.enabled, true)

            backend.browseReply = {success: false, error: "query failed"}
            next.clicked()
            compare(backend.offset, 200)
            verify(summary.text.includes("offset 0"))
            compare(findChild(explorer, "previousPage").enabled, false)
            compare(findChild(explorer, "errorMessage").text, "query failed")

            backend.browseReply = {success: true}
            next.clicked()
            verify(summary.text.includes("offset 200"))
            findChild(explorer, "previousPage").clicked()
            verify(summary.text.includes("offset 0"))
        }

        function test_invokeExceptionClearsPending() {
            explorer.invoke(function() { throw new Error("backend disconnected") })
            compare(explorer.working, false)
            verify(findChild(explorer, "errorMessage").text.includes("backend disconnected"))
        }
    }
}
