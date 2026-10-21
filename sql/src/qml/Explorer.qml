pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Logos.Theme
import Logos.Controls

// Read-only channel browser. Operations run through the remote UI backend;
// only selection, paging and request feedback are kept in this view.
ColumnLayout {
    id: root

    // --- Public API ---
    required property var backend
    required property var resultModel
    // Inject logos.watch so the same view can run with a test backend.
    required property var watch
    property bool ready: false
    readonly property bool connected: ready && backend && backend.connected
    readonly property bool working: d.pending || (ready && backend && backend.busy)
    readonly property int pageSize: Number(rowLimit.currentText)
    spacing: Theme.spacing.medium

    QtObject {
        id: d

        property bool pending: false
        property string error: ""
        property var selectedTable: null
        property int rowOffset: 0
        property bool browsing: false

        readonly property int spinnerSize: 28
        readonly property int tableListWidth: 230
        readonly property int tableListMinWidth: 160
        readonly property int resultsMinWidth: 400
        readonly property int editorHeight: 100
    }

    onReadyChanged: {
        if (ready) {
            d.error = ""
            nodeInput.text = backend.nodeUrl
            channelInput.text = backend.channelId
        } else {
            d.pending = false
            resetSelection()
            d.error = qsTr("The SQL Explorer backend is not available.")
        }
    }

    function resetSelection() {
        d.selectedTable = null
        d.rowOffset = 0
        d.browsing = false
        results.clearSelection()
    }

    // The local pending flag covers the time before the remote busy property
    // arrives. A second click must not queue another open or query meanwhile.
    function invoke(operation, succeeded) {
        if (!ready || working)
            return

        d.pending = true
        d.error = ""
        try {
            watch(operation(), function(reply) {
                d.pending = false
                if (!reply.success) {
                    d.error = reply.error || qsTr("The operation failed.")
                } else {
                    results.clearSelection()
                    if (succeeded)
                        succeeded()
                }
            }, function(message) {
                d.pending = false
                d.error = String(message)
            })
        } catch (exception) {
            d.pending = false
            d.error = String(exception)
        }
    }

    function browse(offset, table) {
        const target = table || d.selectedTable
        if (!target)
            return

        invoke(function() { return backend.browseTable(target.name, offset, pageSize) }, function() {
            d.selectedTable = target
            d.rowOffset = offset
            d.browsing = true
        })
    }

    RowLayout {
        Layout.fillWidth: true
        LogosText {
            text: qsTr("SQL Explorer")
            font.pixelSize: Theme.typography.panelTitleText
            font.weight: Theme.typography.weightBold
        }
        Item { Layout.fillWidth: true }
        LogosSpinner {
            running: root.working
            visible: running
            implicitWidth: d.spinnerSize
            implicitHeight: d.spinnerSize
        }
        LogosText {
            objectName: "connectionStatus"
            text: {
                if (!root.ready)
                    return qsTr("Connecting to backend…")
                if (root.connected)
                    return qsTr("Read-only replica open")
                if (root.working)
                    return qsTr("Syncing channel…")

                return qsTr("No channel open")
            }
            color: Theme.palette.textSecondary
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        LogosText {
            text: qsTr("Recent connections")
            visible: recentConnections.count > 0
        }
        LogosComboBox {
            id: recentConnections
            objectName: "recentConnections"
            Layout.fillWidth: true
            visible: count > 0
            enabled: root.ready && !root.working
            model: root.ready ? root.backend.recentConnections : []
            currentIndex: -1
            displayText: qsTr("Choose a previous connection")
            textRole: "channelId"

            delegate: LogosItemDelegate {
                required property var modelData
                width: recentConnections.width
                text: modelData.nodeUrl + " — " + modelData.channelId
            }

            onActivated: function(index) {
                const connection = model[index]
                nodeInput.text = connection.nodeUrl
                channelInput.text = connection.channelId
            }
        }
        LogosText { text: qsTr("Node URL") }
        LogosTextField {
            id: nodeInput
            objectName: "nodeUrl"
            Layout.fillWidth: true
            enabled: root.ready && !root.working
            placeholderText: "http://127.0.0.1:8080"
        }
        LogosText { text: qsTr("Channel ID") }
        LogosTextField {
            id: channelInput
            objectName: "channelId"
            Layout.fillWidth: true
            enabled: root.ready && !root.working
            placeholderText: qsTr("64 hexadecimal characters")
        }
    }

    RowLayout {
        LogosButton {
            objectName: "openChannel"
            text: root.connected ? qsTr("Switch channel") : qsTr("Open channel")
            enabled: root.ready && !root.working && channelInput.text.trim().length > 0
            onClicked: {
                root.resetSelection()
                root.invoke(function() { return root.backend.openChannel(nodeInput.text, channelInput.text) })
            }
        }
        LogosButton {
            text: qsTr("Close")
            enabled: root.connected && !root.working
            onClicked: {
                root.resetSelection()
                root.invoke(function() { return root.backend.closeChannel() })
            }
        }
        Item { Layout.fillWidth: true }
        LogosText { text: qsTr("Read view") }
        LogosComboBox {
            id: readView
            objectName: "readView"
            model: [qsTr("Latest"), qsTr("Finalized")]
            enabled: root.connected && !root.working
            currentIndex: root.ready && root.backend.readView === "finalized" ? 1 : 0
            onActivated: {
                root.resetSelection()
                root.invoke(function() { return root.backend.refreshSchema(currentIndex === 0 ? "latest" : "finalized") })
            }
        }
        LogosButton {
            text: qsTr("Refresh")
            enabled: root.connected && !root.working
            onClicked: {
                root.resetSelection()
                root.invoke(function() { return root.backend.refreshSchema(root.backend.readView) })
            }
        }
    }

    LogosText {
        objectName: "errorMessage"
        Layout.fillWidth: true
        text: d.error
        textFormat: Text.PlainText
        visible: text.length > 0
        wrapMode: Text.Wrap
        color: Theme.palette.error
    }
    LogosText {
        Layout.fillWidth: true
        text: qsTr("Latest includes unfinalized changes. Finalized follows the chain’s finalization progress. Refresh to read again.")
        wrapMode: Text.Wrap
        color: Theme.palette.textSecondary
    }

    SplitView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        orientation: Qt.Horizontal
        handle: Rectangle {
            implicitWidth: Theme.spacing.tiny
            color: Theme.palette.border
        }

        ColumnLayout {
            SplitView.preferredWidth: d.tableListWidth
            SplitView.minimumWidth: d.tableListMinWidth
            LogosText {
                text: qsTr("Tables and views")
                font.weight: Theme.typography.weightBold
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.connected ? root.backend.tables : []
                ScrollBar.vertical: LogosScrollBar {}
                delegate: LogosItemDelegate {
                    id: tableEntry
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.type === "view" ? qsTr("%1 (view)").arg(modelData.name) : modelData.name
                    highlighted: d.selectedTable !== null && d.selectedTable.name === modelData.name
                    enabled: !root.working
                    contentItem: LogosText {
                        text: tableEntry.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    onClicked: {
                        mode.currentIndex = 0
                        root.browse(0, modelData)
                    }
                }
                LogosText {
                    anchors.fill: parent
                    visible: parent.count === 0
                    text: root.connected ? qsTr("No tables in this view yet. Refresh after replication progresses.") : qsTr("Open a channel to explore its database.")
                    wrapMode: Text.Wrap
                    color: Theme.palette.textSecondary
                }
            }
        }

        ColumnLayout {
            SplitView.fillWidth: true
            SplitView.minimumWidth: d.resultsMinWidth

            LogosTabBar {
                id: mode
                Layout.fillWidth: true
                enabled: !root.working
                LogosTabButton { text: qsTr("Browse") }
                LogosTabButton { text: qsTr("SQL query") }
            }
            LogosScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: d.editorHeight
                visible: mode.currentIndex === 0
                LogosTextArea {
                    objectName: "tableSchema"
                    readOnly: true
                    selectByMouse: true
                    text: d.selectedTable ? d.selectedTable.sql : ""
                    textFormat: TextEdit.PlainText
                    placeholderText: qsTr("Select a table or view to see its schema")
                    font.family: Theme.typography.mono
                    wrapMode: TextEdit.Wrap
                }
            }
            LogosScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: d.editorHeight
                visible: mode.currentIndex === 1
                LogosTextArea {
                    id: sqlInput
                    objectName: "sqlInput"
                    text: "SELECT name, type, sql FROM sqlite_schema ORDER BY name"
                    selectByMouse: true
                    font.family: Theme.typography.mono
                    wrapMode: TextEdit.Wrap
                }
            }
            RowLayout {
                LogosText { text: mode.currentIndex === 0 ? qsTr("Rows per page") : qsTr("Row limit") }
                LogosComboBox {
                    id: rowLimit
                    model: ["200", "500", "1000"]
                    enabled: !root.working
                    onActivated: {
                        if (mode.currentIndex === 0 && d.selectedTable)
                            root.browse(0)
                    }
                }
                LogosButton {
                    objectName: "runQuery"
                    text: qsTr("Run query")
                    visible: mode.currentIndex === 1
                    enabled: root.connected && !root.working && sqlInput.text.trim().length > 0
                    onClicked: {
                        root.invoke(function() { return root.backend.runQuery(sqlInput.text, root.pageSize) }, function() {
                            d.browsing = false
                        })
                    }
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "previousPage"
                    text: qsTr("Previous")
                    visible: d.browsing
                    enabled: !root.working && d.rowOffset > 0
                    onClicked: root.browse(Math.max(0, d.rowOffset - root.pageSize))
                }
                LogosButton {
                    objectName: "nextPage"
                    text: qsTr("Next")
                    visible: d.browsing
                    enabled: !root.working && root.connected && root.backend.truncated
                    onClicked: root.browse(d.rowOffset + root.pageSize)
                }
            }
            ResultTable {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.connected ? root.resultModel : null
            }
            LogosText {
                objectName: "resultSummary"
                Layout.fillWidth: true
                text: {
                    if (!root.connected)
                        return ""

                    const rows = root.backend.returnedRows
                    if (d.browsing && d.selectedTable) {
                        return root.backend.truncated
                            ? qsTr("%1 rows returned · %2 · offset %3 · more rows available")
                                .arg(rows).arg(d.selectedTable.name).arg(d.rowOffset)
                            : qsTr("%1 rows returned · %2 · offset %3")
                                .arg(rows).arg(d.selectedTable.name).arg(d.rowOffset)
                    }

                    return root.backend.truncated
                        ? qsTr("%1 rows returned · query results · more rows available").arg(rows)
                        : qsTr("%1 rows returned · query results").arg(rows)
                }
                textFormat: Text.PlainText
                color: Theme.palette.textSecondary
            }
            LogosText {
                Layout.fillWidth: true
                visible: d.browsing
                text: qsTr("Pages are separate reads and may shift as data changes. Use a query with ORDER BY for explicit ordering.")
                wrapMode: Text.Wrap
                color: Theme.palette.textSecondary
            }
        }
    }
}
