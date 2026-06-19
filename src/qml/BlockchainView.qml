import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
// BlockchainStatus enum (NotStarted/Starting/Running/Stopping/Stopped/Error)
// declared in BlockchainBackend.rep — registered with QML by the replica
// factory plugin.
import Logos.BlockchainBackend 1.0

import "views"

Rectangle {
    id: root

    readonly property var backend: logos.module("blockchain_ui")
    // `ready` can't be a binding on logos.isViewModuleReady(): that's a
    // Q_INVOKABLE method, not a Q_PROPERTY, so the binding wouldn't refresh
    // when the replica transitions to Valid. Drive it from the bridge's
    // viewModuleReadyChanged signal instead.
    property bool ready: false

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "blockchain_ui")
                root.ready = isReady && root.backend !== null
        }
    }

    Component.onCompleted: {
        // Cover the case where the replica is already Valid by the time
        // we attach the Connections handler.
        root.ready = root.backend !== null && logos.isViewModuleReady("blockchain_ui")
    }

    // Models live on the C++ backend and are auto-remoted by ui-host as
    // "<module>/<propertyName>". QML acquires them via logos.model(...).
    readonly property var accountsModel: logos.model("blockchain_ui", "accounts")
    readonly property var logModel: logos.model("blockchain_ui", "logs")

    QtObject {
        id: _d
        function getStatusString(s) {
            switch(s) {
            case BlockchainBackend.NotStarted: return qsTr("Not Started")
            case BlockchainBackend.Starting: return qsTr("Starting...")
            case BlockchainBackend.Running: return qsTr("Running")
            case BlockchainBackend.Stopping: return qsTr("Stopping...")
            case BlockchainBackend.Stopped: return qsTr("Stopped")
            case BlockchainBackend.Error: return qsTr("Error: %1").arg(root.backend.lastErrorMessage)
            default: return qsTr("Unknown")
            }
        }
        function getStatusColor(s) {
            switch(s) {
            case BlockchainBackend.Running: return Theme.palette.success
            case BlockchainBackend.Starting:
            case BlockchainBackend.Stopping: return Theme.palette.warning
            default: return Theme.palette.error
            }
        }
        property int currentPage: 0
    }

    color: Theme.palette.background

    // Loading state before backend connects
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: 12
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connecting to blockchain backend...")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: !root.ready }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        currentIndex: _d.currentPage
        visible: root.ready

        // Page 1: Config choice
        ScrollView {
            id: configChoiceScrollView
            clip: true
            ConfigChoiceView {
                id: configChoiceView
                width: configChoiceScrollView.availableWidth
                userConfigPath: root.backend ? root.backend.userConfig : ""
                deploymentConfigPath: root.backend ? root.backend.deploymentConfig : ""
                generatedUserConfigPath: root.backend ? root.backend.generatedUserConfigPath : ""
                onUserConfigPathSelected: function(path) {
                    if (root.backend) root.backend.userConfig = path
                }
                onDeploymentConfigPathSelected: function(path) {
                    if (root.backend) root.backend.deploymentConfig = path
                }
                onSetPathToConfigsRequested: function() {
                    if (root.backend) root.backend.useGeneratedConfig = false
                    _d.currentPage = 1
                }
                onGenerateRequested: function(outputPath, initialPeers, netPort, blendPort, httpAddr, externalAddress, noPublicIpCheck, deploymentMode, deploymentConfigPath, statePath) {
                    if (!root.backend) return
                    console.log("[BlockchainView] generateRequested: outputPath=", outputPath,
                                "initialPeers=", JSON.stringify(initialPeers),
                                "netPort=", netPort, "blendPort=", blendPort,
                                "httpAddr=", httpAddr, "externalAddress=", externalAddress,
                                "noPublicIpCheck=", noPublicIpCheck, "deploymentMode=", deploymentMode,
                                "deploymentConfigPath=", deploymentConfigPath, "statePath=", statePath)
                    configChoiceView.generateResultSuccess = false
                    configChoiceView.generateResultMessage = ""
                    logos.watch(
                        root.backend.generateConfig(
                            outputPath, initialPeers, netPort, blendPort,
                            httpAddr, externalAddress, noPublicIpCheck,
                            deploymentMode, deploymentConfigPath, statePath),
                        function(code) {
                            // logos.watch stringifies the returned int — coerce back.
                            var rc = parseInt(code, 10)
                            console.log("[BlockchainView] generateConfig success callback: code=", code, "type=", typeof code, "→ rc=", rc)
                            configChoiceView.generateResultSuccess = (rc === 0)
                            configChoiceView.generateResultMessage =
                                rc === 0
                                    ? qsTr("Config generated successfully.")
                                    : qsTr("Generate failed (code: %1).").arg(rc)
                            if (rc === 0) {
                                root.backend.userConfig = (outputPath !== "")
                                    ? outputPath : root.backend.generatedUserConfigPath
                                root.backend.deploymentConfig =
                                    (deploymentMode === 1 && deploymentConfigPath !== "")
                                        ? deploymentConfigPath : ""
                                root.backend.useGeneratedConfig = true
                                _d.currentPage = 1
                            }
                        },
                        function(error) {
                            console.log("[BlockchainView] generateConfig error callback: error=", error)
                            configChoiceView.generateResultSuccess = false
                            configChoiceView.generateResultMessage =
                                qsTr("Generate failed: %1").arg(error)
                        }
                    )
                }
            }
        }

        // Page 2: Node control, wallet, logs
        SplitView {
            orientation: Qt.Vertical

            ColumnLayout {
                SplitView.fillWidth: true
                SplitView.minimumHeight: 200
                spacing: Theme.spacing.large

                StatusConfigView {
                    Layout.fillWidth: true
                    statusText: root.backend
                        ? _d.getStatusString(root.backend.status)
                        : qsTr("Not Connected")
                    statusColor: root.backend
                        ? _d.getStatusColor(root.backend.status)
                        : Theme.palette.error
                    userConfig: root.backend ? root.backend.userConfig : ""
                    deploymentConfig: root.backend ? root.backend.deploymentConfig : ""
                    useGeneratedConfig: root.backend ? root.backend.useGeneratedConfig : false
                    canStart: root.backend
                              && !!root.backend.userConfig
                              && root.backend.status !== BlockchainBackend.Starting
                              && root.backend.status !== BlockchainBackend.Stopping
                    isRunning: root.backend
                               ? root.backend.status === BlockchainBackend.Running
                               : false

                    onStartRequested: if (root.backend) root.backend.startBlockchain()
                    onStopRequested: if (root.backend) root.backend.stopBlockchain()
                    onChangeConfigRequested: _d.currentPage = 0
                }

                WalletView {
                    id: walletView
                    accountsModel: root.accountsModel

                    onGetBalanceRequested: function(addressHex) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.getBalance(addressHex),
                            function(result) {
                                if ((result || "").indexOf("Error") === 0) {
                                    walletView.lastBalanceErrorAddress = addressHex
                                    walletView.lastBalanceError = result
                                } else {
                                    walletView.lastBalanceErrorAddress = ""
                                    walletView.lastBalanceError = ""
                                }
                            },
                            function(error) {
                                walletView.lastBalanceErrorAddress = addressHex
                                walletView.lastBalanceError = "Error: " + error
                            }
                        )
                    }
                    onCopyToClipboard: (text) => {
                        if (root.backend) root.backend.copyToClipboard(text)
                    }
                    onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.transferFunds(fromKeyHex, toKeyHex, amount),
                            function(result) { walletView.setTransferResult(result) },
                            function(error) { walletView.setTransferResult("Error: " + error) }
                        )
                    }
                }

                Item {
                    Layout.preferredHeight: Theme.spacing.small
                }
            }

            LogsView {
                SplitView.fillWidth: true
                SplitView.minimumHeight: 150

                logModel: root.logModel
                onClearRequested: if (root.backend) root.backend.clearLogs()
                onCopyToClipboard: (text) => {
                    if (root.backend) root.backend.copyToClipboard(text)
                }
            }
        }
    }
}
