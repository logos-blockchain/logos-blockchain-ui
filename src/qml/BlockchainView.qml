import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
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

    // Clipboard must be handled here in the UI-host (GUI) process. The backend
    // .rep source runs in a separate, non-GUI ViewModuleHost subprocess where
    // QGuiApplication::clipboard() segfaults (process exits with code 11), so
    // we copy from QML via a hidden TextEdit instead of calling the backend.
    function copyText(text) {
        clipboardHelper.text = text || ""
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
        clipboardHelper.text = ""
    }

    TextEdit {
        id: clipboardHelper
        visible: false
    }

    QtObject {
        id: _d
        function errorText(message) {
            return qsTr("Error: %1").arg(message)
        }

        function getStatusString(s) {
            switch(s) {
            case BlockchainBackend.NotStarted: return qsTr("Not Started")
            case BlockchainBackend.Starting: return qsTr("Starting...")
            case BlockchainBackend.Running: return qsTr("Running")
            case BlockchainBackend.Stopping: return qsTr("Stopping...")
            case BlockchainBackend.Stopped: return qsTr("Stopped")
            case BlockchainBackend.Error: return _d.errorText(root.backend.lastErrorMessage)
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
                        function(result) {
                            console.log("[BlockchainView] generateConfig success callback: result=", JSON.stringify(result))
                            configChoiceView.generateResultSuccess = result.success
                            configChoiceView.generateResultMessage =
                                result.success
                                    ? qsTr("Config generated successfully.")
                                    : qsTr("Generate failed: %1").arg(result.error)
                            if (result.success) {
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

        // Page 2: Node information + Wallet operations (tabbed)
        ColumnLayout {
            id: opPage
            spacing: Theme.spacing.medium

            // Selected operation inside the Operations tab's sidebar nav.
            //   0 Accounts · 1 Transfer · 2 Leader Rewards · 3 Channel Deposit
            property int operationIndex: 0

            readonly property bool nodeRunning: root.backend
                ? root.backend.status === BlockchainBackend.Running
                : false

            // Channel Deposit requires a running node. If the node stops while
            // it's selected, fall back to Accounts so the user isn't stranded
            // on a disabled nav item.
            onNodeRunningChanged: {
                if (!nodeRunning && operationIndex === 3)
                    operationIndex = 0
            }

            LogosTabBar {
                id: operationTabBar
                Layout.fillWidth: true
                LogosTabButton { text: qsTr("Node") }
                LogosTabButton { text: qsTr("Operations") }
            }

            StackLayout {
                id: operationStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: operationTabBar.currentIndex

                // ---- Tab 0: Node information (status + logs) ----
                SplitView {
                    orientation: Qt.Vertical

                    ColumnLayout {
                        SplitView.fillWidth: true
                        SplitView.minimumHeight: 120
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
                            isRunning: opPage.nodeRunning

                            onStartRequested: if (root.backend) root.backend.startBlockchain()
                            onStopRequested: if (root.backend) root.backend.stopBlockchain()
                            onChangeConfigRequested: _d.currentPage = 0
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
                            root.copyText(text)
                        }
                    }
                }

                // ---- Tab 1: Wallet operations (sidebar nav + panels) ----
                RowLayout {
                    spacing: Theme.spacing.large

                    // Sidebar navigation
                    ColumnLayout {
                        Layout.preferredWidth: 180
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.spacing.small

                        NavItem { label: qsTr("Accounts"); index: 0 }
                        NavItem { label: qsTr("Transfer"); index: 1 }
                        NavItem { label: qsTr("Leader Rewards"); index: 2 }
                        NavItem {
                            label: qsTr("Channel Deposit")
                            index: 3
                            itemEnabled: opPage.nodeRunning
                        }

                        Item { Layout.fillHeight: true }
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        color: Theme.palette.borderSecondary
                    }

                    // Operation panels
                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: opPage.operationIndex

                        AccountsView {
                            id: accountsView
                            accountsModel: root.accountsModel

                            onGetBalanceRequested: function(addressHex) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.getBalance(addressHex),
                                    function(result) {
                                        if (result.success) {
                                            accountsView.lastBalanceErrorAddress = ""
                                            accountsView.lastBalanceError = ""
                                        } else {
                                            accountsView.lastBalanceErrorAddress = addressHex
                                            accountsView.lastBalanceError = _d.errorText(result.error)
                                        }
                                    },
                                    function(error) {
                                        accountsView.lastBalanceErrorAddress = addressHex
                                        accountsView.lastBalanceError = _d.errorText(error)
                                    }
                                )
                            }
                            onRefreshAccountsRequested: if (root.backend) root.backend.refreshAccounts()
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }

                        TransferView {
                            id: transferView
                            accountsModel: root.accountsModel

                            onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.transferFunds(fromKeyHex, toKeyHex, amount),
                                    function(result) {
                                        if (result.success) {
                                            transferView.setTransferResult(result.value)
                                        } else {
                                            transferView.setTransferResult(_d.errorText(result.error))
                                        }
                                    },
                                    function(error) { transferView.setTransferResult(_d.errorText(error)) }
                                )
                            }
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }

                        LeaderRewardsView {
                            id: leaderRewardsView

                            onClaimLeaderRewardsRequested: function() {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.claimLeaderRewards(),
                                    function(result) {
                                        if (result.success) {
                                            leaderRewardsView.setLeaderClaimResult(result.value)
                                        } else {
                                            leaderRewardsView.setLeaderClaimResult(_d.errorText(result.error))
                                        }
                                    },
                                    function(error) { leaderRewardsView.setLeaderClaimResult(_d.errorText(error)) }
                                )
                            }
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }

                        ChannelDepositView {
                            id: channelDepositView
                            accountsModel: root.accountsModel
                            nodeRunning: opPage.nodeRunning

                            onGetNotesRequested: function(addressHex, optionalTipHex) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.getNotes(addressHex, optionalTipHex),
                                    function(result) {
                                        if (result.success)
                                            channelDepositView.setNotes(result.value)
                                        else
                                            channelDepositView.setNotesError(_d.errorText(result.error))
                                    },
                                    function(error) { channelDepositView.setNotesError(_d.errorText(error)) }
                                )
                            }
                            onSubmitRequested: function(channelIdHex, inputNoteIdHexes, metadataBase58, changePublicKeyHex, fundingPublicKeyHexes, maxTxFee, optionalTipHex) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.channelDepositWithNotes(
                                        channelIdHex, inputNoteIdHexes, metadataBase58,
                                        changePublicKeyHex, fundingPublicKeyHexes, maxTxFee, optionalTipHex),
                                    function(result) {
                                        if (result.success)
                                            channelDepositView.setSubmitResult(true, result.value)
                                        else
                                            channelDepositView.setSubmitResult(false, _d.errorText(result.error))
                                    },
                                    function(error) { channelDepositView.setSubmitResult(false, _d.errorText(error)) }
                                )
                            }
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }
                    }
                }
            }

            // Sidebar nav entry used by the Operations tab.
            component NavItem: Rectangle {
                property string label
                property int index
                property bool itemEnabled: true

                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.spacing.radiusSmall
                color: opPage.operationIndex === index
                    ? Theme.palette.backgroundTertiary
                    : (navMouse.containsMouse ? Theme.palette.backgroundSecondary : "transparent")
                opacity: itemEnabled ? 1.0 : 0.4

                LogosText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacing.medium
                    anchors.rightMargin: Theme.spacing.medium
                    anchors.verticalCenter: parent.verticalCenter
                    text: label
                    elide: Text.ElideRight
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: opPage.operationIndex === index
                    color: opPage.operationIndex === index
                        ? Theme.palette.primary
                        : Theme.palette.text
                }

                MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    enabled: itemEnabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: opPage.operationIndex = index
                }
            }
        }
    }
}
