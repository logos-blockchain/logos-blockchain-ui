pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls


// First-run setup, and the only way back into configuration afterwards.
ColumnLayout {
    id: root

    // --- Inputs from the host ---

    property string userConfigPath: ""
    property string deploymentConfigPath: ""
    // The keystore for the current config, or empty when there is none yet.
    property string nodeKeystorePath: ""
    property bool keysBackedUp: false
    // Rows { address, label } — every key the keystore holds.
    property var keystoreKeys: []
    // Rows { address, roles, roleLabel, label } for the mining step's picker.
    property var powAccounts: []
    // The pow section the config already holds, so the step opens pre-filled.
    property var powSection: ({})
    // A usable config already exists, so setup can be abandoned. False on a
    // genuine first run, where there is nothing to go back to.
    property bool canExit: false
    // A call is in flight. The footer is the only thing that can start one, so
    // disabling it there is enough to keep the wizard single-threaded.
    property bool busy: false
    property string busyMessage: ""
    // The last failure, cleared on the next attempt. Shown on whichever step is
    // open, because that is the step that caused it.
    property string errorMessage: ""

    // Bootstrap peers for this build, from the module's metadata.json via the
    // backend. Supplied by the host rather than read here: they are node
    // configuration, and the backend is what calls generate_user_config.
    property var bootstrapPeers: []

    // A generated config is already on disk for this app. Survives a view
    // rebuild because it is derived from backend state, not remembered here.
    property bool configExists: false

    // Whether the welcome screen can offer Quick start at all. It cannot ask
    // for bootstrap peers — that is the whole point of it — so with none
    // configured the only node it could build is one that never finds the
    // chain. The landing screen still shows; it just offers the one route that
    // can ask for peers rather than a button that quietly skips them.
    readonly property bool quickStartAvailable: root.bootstrapPeers.length > 0

    // Which screen the request came from. The host needs this to tell quick
    // start's generate — which finishes the flow — from the network step's,
    // which advances it, without the wizard having to say so twice.
    //
    // Not named onWelcomeScreen: a property whose name begins with "on" reads
    // as a signal handler wherever it is assigned.
    readonly property bool atWelcomeScreen: d.step === "welcome"

    // --- Outputs ---

    signal generateRequested(string outputPath, var initialPeers, int netPort, int blendPort,
                             string httpAddr, string externalAddress, bool noPublicIpCheck,
                             int deploymentMode, string deploymentConfigPath, string statePath)
    signal userConfigPathSelected(string path)
    signal deploymentConfigPathSelected(string path)
    signal powConfigureRequested(string configJson)
    signal backupKeystoreRequested(string destinationPath)
    signal finished(bool startNode)
    signal exitRequested()

    function configGenerated() { d.goTo("keys") }
    function powConfigured() { root.finished(true) }

    spacing: Theme.spacing.large

    QtObject {
        id: d

        // "generate" or "existing".
        property string mode: "generate"

        readonly property bool configWritten: root.configExists
        property int stepIndex: -1
        readonly property var steps: mode === "existing"
            ? ["setup"]
            : ["setup", "network", "keys", "fund"]

        readonly property string step: (stepIndex >= 0 && stepIndex < steps.length)
            ? steps[stepIndex]
            : "welcome"

        function indexOf(name) {
            for (var i = 0; i < steps.length; ++i) {
                if (steps[i] === name)
                    return i
            }
            return -1
        }

        function goTo(name) {
            const at = indexOf(name)
            if (at >= 0)
                stepIndex = at
        }

        function next() {
            if (stepIndex < steps.length - 1)
                stepIndex += 1
        }

        function back() {
            if (stepIndex > -1)
                stepIndex -= 1
        }

        function advance() {
            switch (step) {
            case "setup":
                if (mode === "existing")
                    root.finished(true)
                else
                    next()
                break
            case "network":
                if (d.configWritten)
                    next()
                else
                    networkStep.submit()
                break
            case "keys":
                next()
                break
            case "fund":
                miningStep.submit()
                break
            }
        }

        readonly property bool canAdvance: {
            if (root.busy)
                return false
            switch (step) {
            case "setup":
                return mode === "generate"
                    || (mode === "existing" && root.userConfigPath.length > 0)
            case "network":
                // Nothing left to validate once it is written.
                return d.configWritten || networkStep.valid
            case "keys":
                return root.keysBackedUp || keysStep.acknowledged
            case "fund":
                return miningStep.valid
            default:
                return true
            }
        }

        readonly property string advanceHint: {
            if (root.busy || canAdvance)
                return ""
            switch (step) {
            case "setup":
                return mode === "existing"
                    ? qsTr("Choose your user config to continue")
                    : qsTr("Pick how you want to start")
            case "network":
                if (d.configWritten)
                    return ""
                if (networkStep.needsDeployment)
                    return qsTr("Choose a deployment file to continue")
                if (networkStep.needsPeers)
                    return qsTr("Add at least one bootstrap peer to continue")
                return ""
            case "keys":
                return qsTr("Confirm you saved your keys to continue")
            case "fund":
                return miningStep.needsTarget
                    ? qsTr("Add an account for auto-claim to pay, or switch it off")
                    : ""
            default:
                return ""
            }
        }

        readonly property string advanceText: {
            if (root.busy)
                return root.busyMessage.length > 0 ? root.busyMessage : qsTr("Working…")
            switch (step) {
            case "setup":
                return mode === "existing" ? qsTr("Start node") : qsTr("Continue")
            case "network":
                return d.configWritten ? qsTr("See your keys") : qsTr("Generate config")
            case "fund":
                return qsTr("Start node")
            default:
                return qsTr("Continue")
            }
        }

        // Rail labels, index-for-index with `steps` above. Short on purpose:
        // every column is the same width, so a long one only elides.
        readonly property var stepNames: steps.map(function (name) {
            switch (name) {
            case "setup":   return qsTr("Setup")
            case "network": return qsTr("Network")
            case "keys":    return qsTr("Keys")
            case "fund":    return qsTr("Fund")
            default:        return name
            }
        })
    }

    function reset() {
        d.stepIndex = -1
        d.mode = "generate"
        networkStep.reset()
    }

    // ---- Welcome -----------------------------------------------------------

    OnboardingWelcome {
        objectName: "onboardingWelcome"
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: d.step === "welcome"
        busy: root.busy
        busyMessage: root.busyMessage
        errorMessage: root.errorMessage
        canExit: root.canExit
        quickStartAvailable: root.quickStartAvailable
        onQuickStartRequested: root.generateRequested(
            "", root.bootstrapPeers, 0, 0, "", "", false, 0, "", "")
        onAdvancedRequested: d.stepIndex = 0
        onExitRequested: root.exitRequested()
    }

    // ---- Stepper chrome ----------------------------------------------------

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spacing.large
        Layout.rightMargin: Theme.spacing.large
        Layout.topMargin: Theme.spacing.large
        visible: d.step !== "welcome"
        spacing: Theme.spacing.large

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                LogosText {
                    objectName: "onboardingStepTitle"
                    text: qsTr("Set up your node")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.titleText
                    font.weight: Theme.typography.weightBold
                }

                LogosText {
                    objectName: "onboardingStepSubtitle"
                    text: qsTr("Advanced setup — configure and secure your node.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            LogosButton {
                objectName: "onboardingExitButton"
                Layout.alignment: Qt.AlignTop
                visible: root.canExit
                enabled: !root.busy
                text: qsTr("Exit setup")
                onClicked: root.exitRequested()
            }
        }

        RowLayout {
            objectName: "onboardingStepRail"
            visible: d.steps.length > 1
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            Repeater {
                model: d.stepNames

                delegate: ColumnLayout {
                    id: railStep
                    required property int index
                    required property string modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: railStep.index <= d.stepIndex ? Theme.palette.primary
                                                    : Theme.palette.border
                    }

                    LogosText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (railStep.index + 1) + ". " + railStep.modelData
                        color: railStep.index === d.stepIndex ? Theme.palette.text
                                                              : Theme.palette.textTertiary
                        font.pixelSize: OnboardingText.fieldHint
                        font.weight: railStep.index === d.stepIndex
                            ? Theme.typography.weightBold
                            : Theme.typography.weightRegular
                    }
                }
            }
        }
    }

    // ---- Steps -------------------------------------------------------------

    LogosScrollView {
        id: stepScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.spacing.large
        Layout.rightMargin: Theme.spacing.large
        visible: d.step !== "welcome"
        contentWidth: availableWidth

    StackLayout {
        id: stepStack

        width: stepScroll.availableWidth
        height: Math.max(stepScroll.availableHeight, implicitHeight)

        currentIndex: {
            switch (d.step) {
            case "setup":   return 0
            case "network": return 1
            case "keys":    return 2
            case "fund":    return 3
            default:        return 0
            }
        }

        OnboardingSetupStep {
            id: setupStep
            objectName: "onboardingSetupStep"
            mode: d.mode
            userConfigPath: root.userConfigPath
            deploymentConfigPath: root.deploymentConfigPath
            errorMessage: d.step === "setup" ? root.errorMessage : ""
            onModePicked: function(picked) { d.mode = picked }
            onUserConfigPathSelected: function(path) { root.userConfigPathSelected(path) }
            onDeploymentConfigPathSelected: function(path) { root.deploymentConfigPathSelected(path) }
        }

        OnboardingNetworkStep {
            id: networkStep
            objectName: "onboardingNetworkStep"
            busy: root.busy
            locked: d.configWritten
            defaultPeers: root.bootstrapPeers
            userConfigPath: root.userConfigPath
            errorMessage: d.step === "network" ? root.errorMessage : ""
            onSubmitted: function(outputPath, initialPeers, netPort, blendPort, httpAddr,
                                  externalAddress, noPublicIpCheck, deploymentMode,
                                  deploymentPath, statePath) {
                root.generateRequested(outputPath, initialPeers, netPort, blendPort, httpAddr,
                                       externalAddress, noPublicIpCheck, deploymentMode,
                                       deploymentPath, statePath)
            }
        }

        OnboardingKeysStep {
            id: keysStep
            objectName: "onboardingKeysStep"
            keys: root.keystoreKeys
            keystorePath: root.nodeKeystorePath
            alreadyBackedUp: root.keysBackedUp
            errorMessage: d.step === "keys" ? root.errorMessage : ""
            onDownloadRequested: function(path) { root.backupKeystoreRequested(path) }
        }

        OnboardingMiningStep {
            id: miningStep
            objectName: "onboardingMiningStep"
            accounts: root.powAccounts
            powSection: root.powSection
            busy: root.busy
            errorMessage: d.step === "fund" ? root.errorMessage : ""
            onSubmitted: function(configJson) { root.powConfigureRequested(configJson) }
        }
    }
    }

    // ---- Footer ------------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spacing.large
        Layout.rightMargin: Theme.spacing.large
        Layout.bottomMargin: Theme.spacing.large
        visible: d.step !== "welcome"
        spacing: Theme.spacing.medium

        LogosButton {
            objectName: "onboardingBackButton"
            visible: d.stepIndex > -1
            enabled: !root.busy
            text: qsTr("Back")
            onClicked: d.back()
        }

        Item { Layout.fillWidth: true }

        // The one thing the keys step's gate cannot say for itself: the button
        // is disabled and the reason is a checkbox two rows up.
        LogosText {
            objectName: "onboardingAdvanceHint"
            visible: d.advanceHint.length > 0
            text: d.advanceHint
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }

        LogosButton {
            objectName: "onboardingAdvanceButton"
            variant: LogosButton.Variant.Primary
            Layout.preferredHeight: 44
            Layout.minimumWidth: 160
            enabled: d.canAdvance
            text: d.advanceText
            onClicked: d.advance()
        }
    }
}
