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

    // Never-connected and lost-the-connection look identical in `status`, but
    // one is a fresh launch and the other is a node whose status is now stale.
    property bool everReady: false
    onReadyChanged: if (root.ready) root.everReady = true

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

    LogosToast {
        id: stopFailedToast
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.large
    }

    // Self libp2p peer id, derived from the selected user config (no running
    // node required). Refreshed when ready and whenever the config changes.
    property string peerId: ""

    // Skip the first-run chooser when a config already exists. One-shot, so it
    // never overrides a later manual return to the chooser.
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
        function onStopFailed(reason) {
            if (root.quitting && root.Window.window) {
                root.Window.window.close()
                return
            }
            stopFailedToast.show(qsTr("Couldn't stop the node"), reason)
        }
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

    readonly property bool moduleReachable:
        !root.backend || root.backend.nodeModuleReachable === undefined
        || root.backend.nodeModuleReachable


    // The backend polls and derives; this only says whether anyone is looking,
    // which is the one half of it the backend cannot know.
    Binding {
        target: root.backend
        property: "claimablePollActive"
        value: root.nodeRunning && _d.currentPage === 1 && opPage.sectionIndex === 4
        when: root.backend !== null
        restoreMode: Binding.RestoreNone
    }

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
            if (root.backend.status === BlockchainBackend.Running) {
                root.refreshClaimableVouchers()
            } else {
                root.claimableVouchersJson = ""
            }
        }
    }

    QtObject {
        id: _d

        // Last failure from the Fund button, shown on the dashboard's Mining
        // Rewards card — the header has nowhere to put a message.
        property string miningError: ""

        property bool claimBusy: false
        property bool claimSuccess: false
        property string claimMessage: ""

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

        // The config the PoW step edits, captured when the step opens. Held here
        // rather than read back from backend.userConfig at each use: that is a
        // replica property, so it lags a write by a round trip.
        property string powConfigPath: ""

        // Show the PoW step and fill its account picker from the config that was
        // just written. The accounts come from the file rather than the wallet:
        // the node has not started yet, and wallet_get_known_addresses needs one
        // that has. Failing to read them is not fatal — the step still offers
        // "continue without auto-claim", which is a valid configuration.
        function showPowStep(configPath) {
            _d.powConfigPath = configPath || ""
            console.log("[BlockchainView] showPowStep: configPath=", _d.powConfigPath)
            // Cleared before the read, not after it: re-entering the wizard must
            // not offer the previous config's accounts while this one loads.
            configChoiceView.powAccounts = []
            configChoiceView.powBusy = false
            configChoiceView.powResultSuccess = false
            configChoiceView.powResultMessage = ""
            configChoiceView.showPowConfig()

            if (!root.backend || _d.powConfigPath === "") {
                // Say so rather than showing an empty picker: without a path
                // there is nothing to read accounts from and nothing to write
                // back to, and a silent return looks like a config with no keys.
                configChoiceView.powResultMessage =
                    qsTr("Could not tell which config file was written, so accounts cannot be "
                         + "listed. Set the config path and configure PoW from there.")
                return
            }

            logos.watch(
                root.backend.getConfigWalletKeys(_d.powConfigPath),
                function(result) {
                    if (!result.success) {
                        configChoiceView.powResultMessage =
                            qsTr("Could not read accounts from the config: %1").arg(result.error)
                        return
                    }
                    configChoiceView.powAccounts = result.value || []
                    const configured = configChoiceView.powAccounts.length
                    console.log("[BlockchainView] showPowStep: accounts=", configured)
                    if (configured === 0) {
                        configChoiceView.powResultMessage =
                            qsTr("The config lists no wallet keys, so there is nothing to claim "
                                 + "into. Continue without auto-claim, or check wallet.known_keys.")
                    }
                },
                function(error) {
                    configChoiceView.powResultMessage =
                        qsTr("Could not read accounts from the config: %1").arg(error)
                }
            )
        }

        // Runtime override on the node's own default — nothing is written to the
        // config, so this is undone by a node restart rather than by editing the
        // targets back in.
        function setAutoClaim(enabled) {
            if (!root.backend)
                return
            _d.claimMessage = ""
            logos.watch(
                enabled ? root.backend.powStartAutoClaim() : root.backend.powStopAutoClaim(),
                function(result) {
                    if (!result.success) {
                        _d.claimSuccess = false
                        _d.claimMessage = enabled
                            ? qsTr("Could not turn auto-claim on: %1").arg(_d.errorText(result.error))
                            : qsTr("Could not turn auto-claim off: %1").arg(_d.errorText(result.error))
                    }
                },
                function(error) {
                    _d.claimSuccess = false
                    _d.claimMessage = _d.errorText(error)
                }
            )
        }

        // An empty address lets the node pay whichever target is furthest below
        // its threshold, which is the same choice auto-claim makes.
        function claimPowRewards(addressHex) {
            if (!root.backend)
                return
            _d.claimBusy = true
            _d.claimSuccess = false
            _d.claimMessage = ""
            logos.watch(
                root.backend.powClaim(addressHex),
                function(result) {
                    _d.claimBusy = false
                    _d.claimSuccess = result.success
                    _d.claimMessage = result.success
                        ? qsTr("Claim submitted: %1").arg(result.value)
                        : qsTr("Claim failed: %1").arg(_d.errorText(result.error))
                },
                function(error) {
                    _d.claimBusy = false
                    _d.claimSuccess = false
                    _d.claimMessage = qsTr("Claim failed: %1").arg(_d.errorText(error))
                }
            )
        }

        // The whole PoW section goes in one call, so the wizard never leaves the
        // file partly configured. The operator chose these, so a rejection stops
        // the wizard here rather than being warned about and dropped — and since
        // the module validates before writing, a failure means nothing changed.
        function savePowConfig(configJson) {
            if (!root.backend)
                return
            configChoiceView.powBusy = true
            configChoiceView.powResultSuccess = false
            configChoiceView.powResultMessage = ""
            logos.watch(
                root.backend.powConfigure(_d.powConfigPath, configJson),
                function(result) {
                    configChoiceView.powBusy = false
                    configChoiceView.powResultSuccess = result.success
                    if (result.success)
                        configChoiceView.showSetConfigPath()
                    else
                        configChoiceView.powResultMessage =
                            qsTr("Could not save the PoW settings: %1").arg(result.error)
                },
                function(error) {
                    configChoiceView.powBusy = false
                    configChoiceView.powResultSuccess = false
                    configChoiceView.powResultMessage =
                        qsTr("Could not save the PoW settings: %1").arg(error)
                }
            )
        }
    }

    color: Theme.palette.background

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
                onPowConfirmRequested: function(configJson) {
                    _d.savePowConfig(configJson)
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
                                // Resolved once into a local because userConfig
                                // is a replica property: the write below is a
                                // round trip to the source, so reading it back
                                // on this same tick still yields the old value.
                                const resolvedConfigPath =
                                    (result.value !== undefined && result.value !== "")
                                        ? result.value
                                        : (outputPath !== "" ? outputPath : root.backend.generatedUserConfigPath)
                                root.backend.userConfig = resolvedConfigPath
                                root.backend.deploymentConfig =
                                    (deploymentMode === 1 && deploymentConfigPath !== "")
                                        ? deploymentConfigPath : ""
                                root.backend.useGeneratedConfig = true
                                // The config exists now, so PoW can be set up
                                // against it. That step ends on the "set path"
                                // window, which shows the resolved config path
                                // and continues to starting the node.
                                _d.showPowStep(resolvedConfigPath)
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

        // Page 2: the node itself — a persistent header (identity, the Fund
        // mining toggle and the start/stop control) over a tab bar, one tab per
        // section.
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

            readonly property string chainId: root.backend && root.backend.chainId
                ? root.backend.chainId
                : ""
            readonly property bool miningRequested: root.backend ? root.backend.miningRequested : false

            // Wallet operations require a running node. If the node stops while
            // Operations or Explorer is open, fall back to Dashboard so the
            // user isn't stranded on a disabled section.
            onNodeRunningChanged: {
                // Whichever way this went, the message belonged to the previous
                // run of the node and no longer describes anything.
                _d.miningError = ""
                if (!nodeRunning)
                    sectionTabs.currentIndex = 0
            }

            // A node module whose process is gone leaves status frozen at Error,
            // and the only honest offer there is Start: it re-probes, and either
            // the module came back and starts, or it says so again. Stop is the
            // one thing that cannot help, and offering it under a message that
            // reads "start it again" is how the two ended up disagreeing.
            readonly property bool canStart: root.backend
                && !!root.backend.userConfig
                && (root.backend.status === BlockchainBackend.NotStarted
                    || root.backend.status === BlockchainBackend.Stopped
                    || (root.backend.status === BlockchainBackend.Error
                        && !root.moduleReachable))
            // Starting is included deliberately: the start RPC outlives replay
            // and IBD, so a node can sit in Starting for many minutes. Without
            // this there is no way to abort a sync short of killing the app.
            // The backend already permits it (stopBlockchain guards on
            // Running/Starting/Error).
            readonly property bool canStop: root.backend
                && root.moduleReachable
                && (root.backend.status === BlockchainBackend.Running
                    || root.backend.status === BlockchainBackend.Starting
                    || root.backend.status === BlockchainBackend.Error)
            // The one genuinely transient state: the stop is already in flight,
            // so there is nothing to offer until it lands.
            readonly property bool stopping: root.backend
                && root.backend.status === BlockchainBackend.Stopping

            // A stop can legitimately take a while; with a fixed label and a
            // disabled button, slow is indistinguishable from frozen.
            property int stoppingSeconds: 0
            onStoppingChanged: opPage.stoppingSeconds = 0
            Timer {
                interval: 1000
                repeat: true
                running: opPage.stopping
                onTriggered: opPage.stoppingSeconds += 1
            }

            // ---- Header: identity + mining and node controls ----
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

                // Mining pays PoW rewards into the leader's funding key, which
                // is what PoS stakes from — so this is how a fresh node funds
                // itself. Secondary next to the node control: starting the node
                // is still the primary action on this header.
                LogosButton {
                    id: fundMiningButton
                    objectName: "fundMiningButton"
                    text: opPage.miningRequested ? qsTr("Stop Mining") : qsTr("Fund")
                    // Mining against a chain we haven't caught up with burns CPU
                    // for nothing: a ticket is anchored to a recent block hash
                    // and expires outside the acceptance window. Stopping stays
                    // available either way — a node that falls behind while
                    // mining must not trap the user with the CPU still pinned.
                    enabled: opPage.nodeRunning && (opPage.miningRequested || monitor.synced)
                    // The one thing the button cannot say for itself. The
                    // prototype assumed mining stopped at a funding target; this
                    // build has no target and does not stop. What that costs is
                    // spelled out on the Mining tab rather than crammed in here.
                    LogosToolTip {
                        text: qsTr("Mining runs until you stop it")
                        placement: LogosToolTip.Placement.Bottom
                        visible: fundMiningButton.hovered
                    }
                    onClicked: {
                        if (!root.backend)
                            return
                        _d.miningError = ""
                        logos.watch(
                            opPage.miningRequested ? root.backend.powStopMining()
                                          : root.backend.powStartMining(),
                            function(result) {
                                if (!result.success)
                                    _d.miningError = _d.errorText(result.error)
                            },
                            function(error) { _d.miningError = _d.errorText(error) }
                        )
                    }
                }

                LogosButton {
                    objectName: "nodeRunButton"
                    variant: LogosButton.Variant.Primary
                    text: opPage.stopping
                          ? (opPage.stoppingSeconds > 0
                             ? qsTr("Stopping… %1s").arg(opPage.stoppingSeconds)
                             : qsTr("Stopping…"))
                          : opPage.canStop ? qsTr("Stop Node")
                          : qsTr("Start Node")
                    enabled: !opPage.stopping && (opPage.canStop || opPage.canStart)
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
                    objectName: "tabMining"
                    text: qsTr("Mining")
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
                    status: root.backend ? root.backend.status : -1
                    connected: root.ready && root.backend !== null
                    moduleReachable: root.moduleReachable
                    everConnected: root.everReady
                    statusMessage: monitor.error
                                   || (root.backend ? root.backend.lastErrorMessage : "")
                    nodeRecovering: !!root.backend && root.backend.nodeRecovering
                    infoJson: monitor.infoJson
                    timeInfoJson: monitor.timeInfoJson
                    vouchersJson: root.claimableVouchersJson
                    stakeTotal: root.backend ? root.backend.stakeTotal : ""
                    stakeNoteCount: root.backend ? root.backend.stakeNoteCount : 0
                    walletFunded: !!root.backend && root.backend.walletFunded
                    stakeAddresses: root.backend ? root.backend.stakeAddresses : []
                    peerId: root.peerId
                    peerCount: root.backend ? root.backend.peerCount : -1
                    connectionCount: root.backend ? root.backend.connectionCount : -1
                    nodeCpuPercent: root.backend ? root.backend.nodeCpuPercent : -1
                    nodeMemoryMb: root.backend ? root.backend.nodeMemoryMb : -1
                    cpuCount: root.backend ? root.backend.cpuCount : 1
                    nodeDiskUsedMb: root.backend ? root.backend.nodeDiskUsedMb : -1
                    nodeDiskFreeMb: root.backend ? root.backend.nodeDiskFreeMb : -1
                    blendRole: root.backend ? root.backend.blendRole
                                            : BlockchainBackend.Unknown
                    synced: monitor.synced
                    hasBeenOnline: monitor.hasBeenOnline
                    statusStale: monitor.stale
                    statusNextPollSeconds: monitor.nextPollSeconds
                    syncStalled: monitor.stalled
                    blockStreamEnded: monitor.streamEnded
                    genesisPending: monitor.genesisPending
                    genesisUnixMs: monitor.genesisUnixMs
                    uptimeSeconds: (root.backend && root.backend.uptimeSeconds !== undefined)
                                   ? root.backend.uptimeSeconds : 0
                    miningRequested: opPage.miningRequested
                    miningError: _d.miningError
                    powRewardsClaimed: root.backend ? root.backend.powRewardsClaimed : 0
                    powRewardsLepta: root.backend ? root.backend.powRewardsLepta : ""
                    claimableTickets: root.backend ? root.backend.claimableTickets : 0
                    claimsStalled: root.backend ? root.backend.claimsStalled : false
                    powActive: root.backend ? root.backend.powActive : false
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

                // ---- Sections 2-3: wallet operations, one per tab ----
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
                                root.refreshClaimableVouchers()
                            },
                            function(error) { leaderRewardsView.setLeaderClaimResult(_d.errorText(error)) }
                        )
                    }
                    onCopyToClipboard: (text) => {
                        root.copyText(text)
                    }
                }

                // ---- Section 4: Mining (PoW tickets and claiming) ----
                MiningView {
                    id: miningView
                    nodeRunning: opPage.nodeRunning
                    autoClaimRunning: root.backend ? root.backend.autoClaimRunning : false
                    rewardsClaimed: root.backend ? root.backend.powRewardsClaimed : 0
                    rewardsLepta: root.backend ? root.backend.powRewardsLepta : ""
                    accounts: root.backend ? root.backend.accountRows : []

                    claimsStalled: root.backend ? root.backend.claimsStalled : false
                    claimStallSeconds: root.backend ? root.backend.claimStallSeconds : 0
                    claimableTickets: root.backend ? root.backend.claimableTickets : 0
                    soonestExpirySlots: root.backend ? root.backend.soonestExpirySlots : -1
                    soonestExpiryCount: root.backend ? root.backend.soonestExpiryCount : 0
                    claimableLoaded: root.backend ? root.backend.claimableLoaded : false
                    claimableError: root.backend ? root.backend.claimableError : ""

                    claimBusy: _d.claimBusy
                    claimSuccess: _d.claimSuccess
                    claimMessage: _d.claimMessage

                    onAutoClaimToggled: function(enabled) { _d.setAutoClaim(enabled) }
                    onClaimRequested: function(addressHex) { _d.claimPowRewards(addressHex) }
                }

                // ---- Section 5: Explorer (block / transaction lookup) ----
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

                // ---- Section 8: Settings ----
                NodeSettingsView {
                    userConfig: root.backend ? root.backend.userConfig : ""
                    deploymentConfig: root.backend ? root.backend.deploymentConfig : ""
                    useGeneratedConfig: root.backend ? root.backend.useGeneratedConfig : false
                    canChange: !opPage.canStop
                    onChangeConfigRequested: _d.currentPage = 0
                }
            }

            // ---- Footer: which chain everything above belongs to ----------
            RowLayout {
                id: chainFooter

                Layout.fillWidth: true
                spacing: Theme.spacing.tiny
                visible: opPage.chainId.length > 0

                LogosText {
                    objectName: "chainIdFooter"
                    Layout.maximumWidth: root.width * 0.6
                    text: qsTr("Chain ID: %1").arg(opPage.chainId)
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideRight
                }

                LogosCopyButton {
                    value: opPage.chainId
                    size: 16
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

}
