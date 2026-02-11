import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import BlockchainBackend
import Logos.DesignSystem

Rectangle {
    id: root

    QtObject {
        id: _d
        function getStatusString(status) {
            switch(status) {
            case BlockchainBackend.NotStarted: return "Not Started";
            case BlockchainBackend.Starting: return "Starting...";
            case BlockchainBackend.Running: return "Running";
            case BlockchainBackend.Stopping: return "Stopping...";
            case BlockchainBackend.Stopped: return "Stopped";
            case BlockchainBackend.Error: return "Error";
            case BlockchainBackend.ErrorNotInitialized: return "Error: Module not initialized";
            case BlockchainBackend.ErrorConfigMissing: return "Error: Config path missing";
            case BlockchainBackend.ErrorStartFailed: return "Error: Failed to start node";
            case BlockchainBackend.ErrorStopFailed: return "Error: Failed to stop node";
            case BlockchainBackend.ErrorSubscribeFailed: return "Error: Failed to subscribe to events";
            default: return "Unknown";
            }
        }
        function getStatusColor(status) {
            switch(status) {
            case BlockchainBackend.Running: return Theme.palette.success;
            case BlockchainBackend.Starting: return Theme.palette.warning;
            case BlockchainBackend.Stopping: return Theme.palette.warning;
            case BlockchainBackend.NotStarted: return Theme.palette.error;
            case BlockchainBackend.Stopped: return Theme.palette.error;
            case BlockchainBackend.Error:
            case BlockchainBackend.ErrorNotInitialized:
            case BlockchainBackend.ErrorConfigMissing:
            case BlockchainBackend.ErrorStartFailed:
            case BlockchainBackend.ErrorStopFailed:
            case BlockchainBackend.ErrorSubscribeFailed: return Theme.palette.error;
            default: return Theme.palette.textSecondary;
            }
        }
    }

    color: Theme.palette.background

    Connections {
        target: backend
        function onLogMessage(message) {
            logsContainer.logsText += message
        }
        function onNewBlockMessage(message) {
            logsContainer.logsText += message
        }
        function onLogsCleared() {
            logsContainer.logsText = ""
        }
    }

    SplitView {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        orientation: Qt.Vertical

        // Tpp: Status and Controls
        ColumnLayout {
            SplitView.fillWidth: true
            SplitView.minimumHeight: 200
            SplitView.preferredHeight: implicitHeight
            spacing: Theme.spacing.large

            // Status Card
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width * 0.9
                implicitHeight: content.implicitHeight + 2 * Theme.spacing.large
                Layout.preferredHeight: implicitHeight
                color: Theme.palette.backgroundTertiary
                radius: Theme.spacing.radiusLarge
                border.color: Theme.palette.border
                border.width: 1

                ColumnLayout {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacing.large
                    spacing: Theme.spacing.medium

                    Text {
                        Layout.alignment: Qt.AlignLeft
                        font.pixelSize: 14//Theme.typography.primaryText
                        font.bold: true
                        text: _d.getStatusString(backend.status)
                        color: _d.getStatusColor(backend.status)
                    }

                    // Chain info
                    Text {
                        Layout.alignment: Qt.AlignLeft
                        Layout.topMargin: -Theme.spacing.medium
                        text: "Mainnet - chain ID 1"
                        font.pixelSize: 12//Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }

                    // Start/Stop Button
                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: parent.width
                        Layout.preferredHeight: 50

                        background: Rectangle {
                            color: parent.pressed || parent.hovered ?
                                       Theme.palette.backgroundMuted:
                                       Theme.palette.backgroundSecondary
                            radius: Theme.spacing.radiusXlarge
                            border.color: Theme.palette.border
                            border.width: 1
                        }

                        enabled: !!backend.configPath && backend.status !== BlockchainBackend.Starting && backend.status !== BlockchainBackend.Stopping
                        text: backend.status === BlockchainBackend.Running ? "Stop Node" : "Start Node"
                        onClicked: {
                            if (backend.status === BlockchainBackend.Running) {
                                backend.stopBlockchain()
                            } else {
                                backend.startBlockchain()
                            }
                        }
                    }
                }
            }

            // Status Card
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width * 0.9
                implicitHeight: content2.implicitHeight + 2 * Theme.spacing.large
                Layout.preferredHeight: implicitHeight
                color: Theme.palette.backgroundTertiary
                radius: Theme.spacing.radiusLarge
                border.color: Theme.palette.border
                border.width: 1

                RowLayout {
                    id: content2

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacing.large
                    spacing: Theme.spacing.medium

                    ColumnLayout {
                        Text {
                            text: "Current Config: "
                            font.pixelSize: 14//Theme.typography.primary
                            font.bold: true
                            color: Theme.palette.text
                        }
                        // Config Path (collapsible/minimal)
                        Text {
                            text: (backend.configPath || "No file selected")
                            font.pixelSize: 12//Theme.typography.secondary
                            color: Theme.palette.textSecondary
                            elide: Text.ElideMiddle
                        }
                    }

                    // Choose New Config file
                    Button {
                        Layout.alignment: Qt.AlignRight
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 50

                        background: Rectangle {
                            color: parent.pressed || parent.hovered ?
                                       Theme.palette.backgroundMuted:
                                       Theme.palette.backgroundSecondary
                            radius: Theme.spacing.radiusXlarge
                            border.color: Theme.palette.border
                            border.width: 1
                        }

                        text: qsTr("Change")
                        onClicked: {
                            fileDialog.open()
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Right: Logs
        Item {
            id: logsPane
            SplitView.fillWidth: true
            SplitView.minimumHeight: 200
            SplitView.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.large
                spacing: Theme.spacing.medium

                // Logs header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    Text {
                        text: "Logs"
                        font.pixelSize: Theme.typography.secondaryText
                        font.bold: true
                        color: Theme.palette.text
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Clear"
                        font.pixelSize: Theme.typography.secondaryText
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 32
                        onClicked: backend.clearLogs()
                    }
                }

                // Logs view (accumulated from logMessage signals)
                Item {
                    id: logsContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    property string logsText: ""


                    ScrollView {
                        anchors.fill: parent
                        clip: true

                        background: Rectangle {
                            color: Theme.palette.backgroundSecondary
                            radius: Theme.spacing.radiusLarge
                            border.color: Theme.palette.border
                            border.width: 1
                        }

                        TextArea {
                            id: logsTextArea
                            readOnly: true
                            text: logsContainer.logsText || "No logs yet..."
                            font.pixelSize: Theme.typography.secondaryText
                            font.family: "Monaco, Menlo, Courier, monospace"
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            color: Theme.palette.text
                            padding: Theme.spacing.medium

                            background: Rectangle {
                                color: "transparent"
                            }

                            onTextChanged: {
                                cursorPosition = text.length
                            }
                        }
                    }
                }
            }
        }
    }
    FileDialog {
        id: fileDialog
        modality: Qt.NonModal
        nameFilters: ["YAML files (*.yaml)"]
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: {
            backend.configPath = selectedFile
        }
    }
}
