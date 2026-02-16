import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import BlockchainBackend
import Logos.Theme

import views

Rectangle {
    id: root

    QtObject {
        id: _d
        function getStatusString(status) {
            switch(status) {
            case BlockchainBackend.NotStarted: return qsTr("Not Started");
            case BlockchainBackend.Starting: return qsTr("Starting...");
            case BlockchainBackend.Running: return qsTr("Running");
            case BlockchainBackend.Stopping: return qsTr("Stopping...");
            case BlockchainBackend.Stopped: return qsTr("Stopped");
            case BlockchainBackend.Error: return qsTr("Error");
            case BlockchainBackend.ErrorNotInitialized: return qsTr("Error: Module not initialized");
            case BlockchainBackend.ErrorConfigMissing: return qsTr("Error: Config path missing");
            case BlockchainBackend.ErrorStartFailed: return qsTr("Error: Failed to start node");
            case BlockchainBackend.ErrorStopFailed: return qsTr("Error: Failed to stop node");
            case BlockchainBackend.ErrorSubscribeFailed: return qsTr("Error: Failed to subscribe to events");
            default: return qsTr("Unknown");
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

    SplitView {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        orientation: Qt.Vertical

        // Top: Status/Config + Wallet side-by-side
        RowLayout {
            SplitView.fillWidth: true
            SplitView.minimumHeight: 200

            StatusConfigView {
                Layout.preferredWidth: parent.width / 2
                statusText: _d.getStatusString(backend.status)
                statusColor: _d.getStatusColor(backend.status)
                configPath: backend.configPath
                canStart: !!backend.configPath
                         && backend.status !== BlockchainBackend.Starting
                         && backend.status !== BlockchainBackend.Stopping
                isRunning: backend.status === BlockchainBackend.Running

                onStartRequested: backend.startBlockchain()
                onStopRequested: backend.stopBlockchain()
                onChangeConfigRequested: fileDialog.open()
            }

            WalletView {
                id: walletView
                Layout.preferredWidth: parent.width / 2

                onGetBalanceRequested: function(addressHex) {
                    walletView.setBalanceResult(backend.getBalance(addressHex))
                }
                onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                    walletView.setTransferResult(backend.transferFunds(fromKeyHex, toKeyHex, amount))
                }
            }
        }

        // Bottom: Logs
        LogsView {
            SplitView.fillWidth: true
            SplitView.minimumHeight: 150

            logModel: backend.logModel
            onClearRequested: backend.clearLogs()
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
