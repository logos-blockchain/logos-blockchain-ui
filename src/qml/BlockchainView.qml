import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import BlockchainBackend
import Logos.Theme

import "views"

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
        property int currentPage: 0  // 0 = config choice (page 1), 1 = node + wallet + logs (page 2)
    }

    color: Theme.palette.background

    StackLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        currentIndex: _d.currentPage

        // Page 1: Config choice (Option 1: Generate own config, Option 2: Set path to configs)
        ScrollView {
            id: configChoiceScrollView
            clip: true
            ConfigChoiceView {
                id: configChoiceView
                width: configChoiceScrollView.availableWidth
                userConfigPath: backend.userConfig
                deploymentConfigPath: backend.deploymentConfig
                generatedUserConfigPath: backend.generatedUserConfigPath
                onUserConfigPathSelected: function(path) { backend.userConfig = path }
                onDeploymentConfigPathSelected: function(path) { backend.deploymentConfig = path }
                onSetPathToConfigsRequested: function() {
                    backend.useGeneratedConfig = false
                    _d.currentPage = 1
                }
                onGenerateRequested: function(outputPath, initialPeers, netPort, blendPort, httpAddr, externalAddress, noPublicIpCheck, deploymentMode, deploymentConfigPath, statePath) {
                    configChoiceView.generateResultSuccess = false
                    configChoiceView.generateResultMessage = ""
                    var code = backend.generateConfig(outputPath, initialPeers, netPort, blendPort, httpAddr, externalAddress, noPublicIpCheck, deploymentMode, deploymentConfigPath, statePath)
                    configChoiceView.generateResultSuccess = (code === 0)
                    configChoiceView.generateResultMessage = code === 0 ? qsTr("Config generated successfully.") : qsTr("Generate failed (code: %1).").arg(code)
                    if (code === 0) {
                        backend.userConfig = (outputPath !== "") ? outputPath : backend.generatedUserConfigPath
                        backend.deploymentConfig = (deploymentMode === 1 && deploymentConfigPath !== "") ? deploymentConfigPath : ""
                        backend.useGeneratedConfig = true
                        _d.currentPage = 1
                    }
                }
            }
        }

        // Page 2: Start node, balances, transfer, logs
        SplitView {
            orientation: Qt.Vertical

            RowLayout {
                SplitView.fillWidth: true
                SplitView.minimumHeight: 200

                StatusConfigView {
                    Layout.preferredWidth: parent.width / 2
                    statusText: _d.getStatusString(backend.status)
                    statusColor: _d.getStatusColor(backend.status)
                    userConfig: backend.userConfig
                    deploymentConfig: backend.deploymentConfig
                    useGeneratedConfig: backend.useGeneratedConfig
                    canStart: !!backend.userConfig
                             && backend.status !== BlockchainBackend.Starting
                             && backend.status !== BlockchainBackend.Stopping
                    isRunning: backend.status === BlockchainBackend.Running

                    onStartRequested: backend.startBlockchain()
                    onStopRequested: backend.stopBlockchain()
                    onChangeConfigRequested: _d.currentPage = 0
                }

                WalletView {
                    id: walletView
                    Layout.preferredWidth: parent.width / 2
                    knownAddresses: backend.knownAddresses

                    onGetBalanceRequested: function(addressHex) {
                        walletView.setBalanceResult(backend.getBalance(addressHex))
                    }
                    onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                        walletView.setTransferResult(backend.transferFunds(fromKeyHex, toKeyHex, amount))
                    }
                }
            }

            LogsView {
                SplitView.fillWidth: true
                SplitView.minimumHeight: 150

                logModel: backend.logModel
                onClearRequested: backend.clearLogs()
                onCopyToClipboard: (text) => backend.copyToClipboard(text)
            }
        }
    }

}
