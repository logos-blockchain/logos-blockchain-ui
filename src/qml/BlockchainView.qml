import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import Logos.Theme
import Logos.Controls
// BlockchainStatus enum (NotStarted/Starting/Running/Stopping/Stopped/Error)
// declared in BlockchainBackend.rep — registered with QML by the replica
// factory plugin.
import Logos.BlockchainBackend 1.0

import "controls"
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
            if (moduleName === "blockchain_ui") {
                root.ready = isReady && root.backend !== null
                if (root.ready) {
                    root.refreshPeerId()
                    root._applyInitialRoute()
                }
            }
        }
    }

    Component.onCompleted: {
        // Cover the case where the replica is already Valid by the time
        // we attach the Connections handler.
        root.ready = root.backend !== null && logos.isViewModuleReady("blockchain_ui")
        if (root.ready) {
            root.refreshPeerId()
            root._applyInitialRoute()
        }
    }

    // Graceful shutdown: if the window is closed while the node is running,
    // veto the close, stop the node, then close once it has stopped.
    property bool quitting: false

    function _nodeBusy() {
        return root.backend
            && (root.backend.status === BlockchainBackend.Running
                || root.backend.status === BlockchainBackend.Starting
                || root.backend.status === BlockchainBackend.Stopping)
    }

    Connections {
        target: root.Window.window
        enabled: root.Window.window !== null
        ignoreUnknownSignals: true
        function onClosing(close) {
            if (!root.quitting && root._nodeBusy()) {
                root.quitting = true
                close.accepted = false
                root.backend.stopBlockchain()
            }
        }
    }

    // Once the stop initiated above completes, finish closing the window.
    Connections {
        target: root.backend
        enabled: root.quitting && root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.quitting && !root._nodeBusy() && root.Window.window)
                root.Window.window.close()
        }
    }

    // Models live on the C++ backend and are auto-remoted by ui-host as
    // "<module>/<propertyName>". QML acquires them via logos.model(...).
    readonly property var accountsModel: logos.model("blockchain_ui", "accounts")
    readonly property var blockModel: logos.model("blockchain_ui", "blocks")

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

    // Self libp2p peer id, derived from the selected user config (no running
    // node required). Refreshed when ready and whenever the config changes.
    property string peerId: ""

    // Open directly on the node view when a config already exists, instead of
    // re-walking the first-run chooser every launch (logos-blockchain-ui#36).
    // The backend restores userConfig from QSettings at construction, so the
    // path is populated by the time the module is ready. Routing only — the
    // operator still starts the node from the node view; the "Change" button
    // there is the path back to the chooser (page 0). One-shot, so it never
    // overrides a manual return to the chooser.
    function _applyInitialRoute() {
        if (_d.initialRouted || !root.ready || !root.backend)
            return
        _d.initialRouted = true
        if (root.backend.userConfig && root.backend.userConfig.length > 0)
            _d.currentPage = 1
    }

    function refreshPeerId() {
        if (!root.backend || !root.backend.userConfig) {
            root.peerId = ""
            return
        }
        logos.watch(
            root.backend.getPeerId(),
            function(result) { root.peerId = result.success ? result.value : "" },
            function(error) { root.peerId = "" }
        )
    }

    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onUserConfigChanged() { root.refreshPeerId() }
        // Ticks per block the node processes, including while it catches up.
        // The count itself is meaningless; the change is the proof of life.
        function onProcessedBlockCountChanged() { monitor.nodeProvedAlive() }
    }

    // Node status. Owns its own timers, backoff, sync debounce and progress
    // tracking; see controls/NodeStatusMonitor.qml. Sits outside any layout
    // because it is an Item with no visual presence.
    NodeStatusMonitor {
        id: monitor
        backend: root.backend
        running: root.nodeRunning
    }

    readonly property bool nodeRunning:
        root.ready && root.backend
        && root.backend.status === BlockchainBackend.Running

    // Wallet's claimable ("pending") vouchers. Auto-refreshed on every incoming
    // block, and once when the node starts running.
    property string claimableVouchersJson: ""

    function refreshClaimableVouchers() {
        if (!root.backend || root.backend.status !== BlockchainBackend.Running)
            return
        logos.watch(
            root.backend.getClaimableVouchers(),
            function(result) { if (result.success) root.claimableVouchersJson = result.value },
            function(error) { /* keep last known list on transient errors */ }
        )
    }

    // Incoming blocks arrive as row insertions on the remoted block model. A
    // new block is proof the node is alive, so it also collapses any status-poll
    // backoff instead of making the user wait the interval out.
    Connections {
        target: root.blockModel
        enabled: root.blockModel !== null
        ignoreUnknownSignals: true
        function onRowsInserted() {
            monitor.nodeProvedAlive()
            root.refreshClaimableVouchers()
        }
    }

    // Initial load when the node reaches Running (before the next block).
    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.backend.status === BlockchainBackend.Running)
                root.refreshClaimableVouchers()
        }
    }

    QtObject {
        id: _d
        // For one-shot results (a failed claim, an explorer lookup) that have no
        // surrounding state to frame them. Deliberately not used for the status
        // poll: its message lands in the hero's sub-line under a headline that
        // already gives the verdict, and a replaying node answers that call with
        // a diagnosed *progress* message which "Error: " would contradict.
        function errorText(message) {
            return qsTr("Error: %1").arg(message)
        }

        property int currentPage: 0

        // Guards the one-time startup route (see root._applyInitialRoute):
        // it must fire once when the module first becomes ready, and never
        // fight the user's later navigation (e.g. the node view's "Change"
        // button, which deliberately returns to the chooser at page 0).
        property bool initialRouted: false
    }

    color: Theme.palette.background

    // Loading state before backend connects
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: Theme.spacing.medium
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connecting to blockchain backend...")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosSpinner { Layout.alignment: Qt.AlignHCenter; running: !root.ready }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        currentIndex: _d.currentPage
        visible: root.ready

        // Page 1: Config choice
        LogosScrollView {
            id: configChoiceScrollView
            ConfigChoiceView {
                id: configChoiceView
                objectName: "configChoiceView"
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
                                // The module writes the config and returns the
                                // absolute path it used; use that for start().
                                root.backend.userConfig =
                                    (result.value !== undefined && result.value !== "")
                                        ? result.value
                                        : (outputPath !== "" ? outputPath : root.backend.generatedUserConfigPath)
                                root.backend.deploymentConfig =
                                    (deploymentMode === 1 && deploymentConfigPath !== "")
                                        ? deploymentConfigPath : ""
                                root.backend.useGeneratedConfig = true
                                // Finalize: move to the "set path" window, now
                                // showing the resolved config path, ready for
                                // the user to continue and start the node.
                                configChoiceView.showSetConfigPath()
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

        // Page 2: the node itself — a persistent header (identity + the one
        // start/stop control) over a tab bar, one tab per section.
        ColumnLayout {
            id: opPage
            spacing: Theme.spacing.medium

            // Selected section. The tab bar and the StackLayout's children are
            // index-for-index: 0 Dashboard · 1 Blocks · 2 Accounts · 3 Rewards ·
            // 4 Explorer · 5 Transfer · 6 Channel Deposit · 7 Settings.
            // Reorder one and you must reorder the other.
            //
            // The tab bar owns the selection. Binding its currentIndex to a
            // property here instead would break the moment the user clicked a
            // tab — TabBar assigns currentIndex itself, which destroys the
            // binding and leaves programmatic navigation with nothing to drive.
            readonly property int sectionIndex: sectionTabs.currentIndex

            readonly property bool nodeRunning: root.backend
                ? root.backend.status === BlockchainBackend.Running
                : false

            // Wallet operations require a running node. If the node stops while
            // Operations or Explorer is open, fall back to Dashboard so the
            // user isn't stranded on a disabled section.
            onNodeRunningChanged: {
                if (!nodeRunning)
                    sectionTabs.currentIndex = 0
            }

            readonly property bool canStart: root.backend
                && !!root.backend.userConfig
                && (root.backend.status === BlockchainBackend.NotStarted
                    || root.backend.status === BlockchainBackend.Stopped)
            readonly property bool canStop: root.backend
                && (root.backend.status === BlockchainBackend.Running
                    || root.backend.status === BlockchainBackend.Error)

            // ---- Header: identity + node control ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                // The Logos mark, not a node glyph. The asset is a 48:66 lambda,
                // so a 30x30 box renders it 22x30 — LogosIcon preserves aspect.
                LogosIcon {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    source: Qt.resolvedUrl("icons/logos.svg")
                    color: Theme.palette.text
                }

                LogosText {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Blockchain Node")
                    color: Theme.palette.text
                    // 28 sits between panelTitleText (24) and titleText (30);
                    // no token matches, and the design measures at 28.
                    font.pixelSize: 28
                    font.weight: Theme.typography.weightBold
                }

                Item { Layout.fillWidth: true }

                LogosButton {
                    objectName: "nodeRunButton"
                    variant: LogosButton.Variant.Primary
                    text: opPage.canStop ? qsTr("Stop Node") : qsTr("Start Node")
                    enabled: opPage.canStop ? opPage.canStop : opPage.canStart
                    onClicked: {
                        if (!root.backend)
                            return
                        if (opPage.canStop)
                            root.backend.stopBlockchain()
                        else
                            root.backend.startBlockchain()
                    }
                }
            }

            LogosTabBar {
                id: sectionTabs
                objectName: "sectionTabs"
                Layout.fillWidth: true

                // Index-for-index with operationStack's children below.
                LogosTabButton {
                    objectName: "tabDashboard"
                    text: qsTr("Dashboard")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTabButton {
                    objectName: "tabBlocks"
                    text: qsTr("Blocks")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTabButton {
                    objectName: "tabAccounts"
                    text: qsTr("Accounts")
                    font.pixelSize: Theme.typography.secondaryText
                    enabled: opPage.nodeRunning
                }
                LogosTabButton {
                    objectName: "tabRewards"
                    text: qsTr("Rewards")
                    font.pixelSize: Theme.typography.secondaryText
                    enabled: opPage.nodeRunning
                }
                LogosTabButton {
                    objectName: "tabExplorer"
                    text: qsTr("Explorer")
                    font.pixelSize: Theme.typography.secondaryText
                    enabled: opPage.nodeRunning
                }
                LogosTabButton {
                    objectName: "tabTransfer"
                    text: qsTr("Transfer")
                    font.pixelSize: Theme.typography.secondaryText
                    enabled: opPage.nodeRunning
                }
                LogosTabButton {
                    objectName: "tabChannelDeposit"
                    text: qsTr("Channel Deposit")
                    font.pixelSize: Theme.typography.secondaryText
                    enabled: opPage.nodeRunning
                }
                LogosTabButton {
                    objectName: "tabSettings"
                    text: qsTr("Settings")
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            StackLayout {
                id: operationStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: opPage.sectionIndex

                // ---- Section 0: Dashboard ----
                NodeDashboardView {
                    accountsModel: root.accountsModel
                    status: root.backend ? root.backend.status : -1
                    statusMessage: monitor.error
                                   || (root.backend ? root.backend.lastErrorMessage : "")
                    nodeRecovering: !!root.backend && root.backend.nodeRecovering
                    infoJson: monitor.infoJson
                    timeInfoJson: monitor.timeInfoJson
                    vouchersJson: root.claimableVouchersJson
                    peerId: root.peerId
                    blendRole: root.backend ? root.backend.blendRole
                                            : BlockchainBackend.Unknown
                    synced: monitor.synced
                    hasBeenOnline: monitor.hasBeenOnline
                    statusStale: monitor.stale
                    statusNextPollSeconds: monitor.nextPollSeconds
                    syncStalled: monitor.stalled
                    blockStreamEnded: monitor.streamEnded
                }

                // ---- Section 1: Blocks ----
                BlocksView {
                    emptyText: !opPage.nodeRunning
                               ? qsTr("Start the node to see blocks arrive.")
                               : monitor.infoJson.length === 0
                                 ? qsTr("Waiting for the node to report its state...")
                                 : qsTr("Waiting for the next block. Only blocks produced from now on are listed.")

                    blockModel: root.blockModel
                    onClearRequested: if (root.backend) root.backend.clearBlocks()
                    onCopyToClipboard: (text) => {
                        root.copyText(text)
                    }
                }

                // ---- Sections 2-6: wallet operations, one per tab ----
                AccountsView {
                    id: accountsView
                    accountsModel: root.accountsModel

                    onGetBalanceRequested: function(addressHex) {
                        if (!root.backend) {
                            accountsView.setBalanceResult(
                                addressHex, false, qsTr("Not connected to the module."))
                            return
                        }
                        logos.watch(
                            root.backend.getBalance(addressHex),
                            function(result) {
                                accountsView.setBalanceResult(
                                    addressHex, result.success,
                                    result.success ? "" : _d.errorText(result.error))
                            },
                            function(error) {
                                accountsView.setBalanceResult(
                                    addressHex, false, _d.errorText(error))
                            }
                        )
                    }
                    onRefreshAccountsRequested: if (root.backend) root.backend.refreshAccounts()
                    onCopyToClipboard: (text) => {
                        root.copyText(text)
                    }
                }

                LeaderRewardsView {
                    id: leaderRewardsView
                    vouchersJson: root.claimableVouchersJson

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
                                // Reflect the claim in the pending list.
                                root.refreshClaimableVouchers()
                            },
                            function(error) { leaderRewardsView.setLeaderClaimResult(_d.errorText(error)) }
                        )
                    }
                    onCopyToClipboard: (text) => {
                        root.copyText(text)
                    }
                }

                // ---- Section 4: Explorer (block / transaction lookup) ----
                ExplorerView {
                    id: explorerView
                    nodeRunning: opPage.nodeRunning

                    // Auto-detect the id kind. The node can't fetch a mined
                    // transaction by hash (its tx store is mempool-only, pruned
                    // ~10 min after inclusion), so resolve a tx in this order:
                    //   1. loaded blocks — the blocks view already holds each
                    //      tx and its id, so a copied tx id resolves locally;
                    //   2. get_block — the id is a block header id;
                    //   3. get_transaction — a still-pending mempool tx.
                    onSearchRequested: function(id) {
                        if (!root.backend) return

                        // Every backend call is remoted through QtRO, so each
                        // must be resolved via logos.watch (even the local scan,
                        // whose search runs synchronously on the source side).

                        // Step 1: scan the loaded blocks for the tx by its id.
                        logos.watch(
                            root.backend.findTransactionInBlocks(id),
                            function(local) {
                                if (local.success) {
                                    explorerView.setTransactionResult(id, local.value, local.slot, local.blockId)
                                    return
                                }
                                // Step 2: block by header id.
                                logos.watch(
                                    root.backend.getBlock(id),
                                    function(blockResult) {
                                        if (blockResult.success) {
                                            explorerView.setBlockResult(id, blockResult.value)
                                            return
                                        }
                                        // Step 3: pending transaction via the node.
                                        logos.watch(
                                            root.backend.getTransaction(id),
                                            function(txResult) {
                                                if (txResult.success)
                                                    explorerView.setTransactionResult(id, txResult.value)
                                                else
                                                    explorerView.setNotFound(id)
                                            },
                                            function(error) { explorerView.setError(id, _d.errorText(error)) }
                                        )
                                    },
                                    function(error) { explorerView.setError(id, _d.errorText(error)) }
                                )
                            },
                            function(error) { explorerView.setError(id, _d.errorText(error)) }
                        )
                    }
                    onCopyToClipboard: (text) => root.copyText(text)
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
                                    transferView.setTransferHash(result.value)
                                } else {
                                    transferView.setTransferError(_d.errorText(result.error))
                                }
                            },
                            function(error) { transferView.setTransferError(_d.errorText(error)) }
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

                // ---- Section 7: Settings ----
                NodeSettingsView {
                    userConfig: root.backend ? root.backend.userConfig : ""
                    deploymentConfig: root.backend ? root.backend.deploymentConfig : ""
                    useGeneratedConfig: root.backend ? root.backend.useGeneratedConfig : false
                    canChange: !opPage.canStop
                    onChangeConfigRequested: _d.currentPage = 0
                }
            }
        }
    }

}
