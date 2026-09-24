import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// The whole first-run flow, self-contained.
Item {
    id: root

    // --- Inputs ---

    property var backend: null
    // A usable config already exists, so setup can be abandoned.
    property bool canExit: false

    // --- Outputs ---

    signal finished(bool startNode)
    signal exitRequested()
    signal keystoreSaved(string path)

    function begin() {
        onboardingView.reset()
        d.setupError = ""
        d.setupBusy = false
        if (root.backend && root.backend.userConfig.length > 0) {
            d.loadPowAccounts(root.backend.userConfig)
            d.loadKeystoreKeys(root.backend.userConfig)
        }
    }

    QtObject {
        id: d

        property bool setupBusy: false
        property string setupBusyMessage: ""
        property string setupError: ""
        property string powConfigPath: ""

        function loadPowAccounts(configPath) {
            d.powConfigPath = configPath || ""
            onboardingView.powAccounts = []
            if (!root.backend || d.powConfigPath === "")
                return
            logos.watch(root.backend.getPowConfig(d.powConfigPath),
                        function(result) {}, function(error) {})
            logos.watch(
                root.backend.getConfigWalletKeys(d.powConfigPath),
                function(result) {
                    onboardingView.powAccounts = result.success ? (result.value || []) : []
                },
                function(error) { onboardingView.powAccounts = [] })
        }

        function loadKeystoreKeys(configPath) {
            onboardingView.keystoreKeys = []
            if (!root.backend || !configPath || configPath.length === 0)
                return
            logos.watch(
                root.backend.getKeystoreKeys(configPath),
                function(result) {
                    onboardingView.keystoreKeys = result.success ? (result.value || []) : []
                },
                function(error) { onboardingView.keystoreKeys = [] })
        }

        function generateConfig(outputPath, initialPeers, netPort, blendPort, httpAddr,
                                externalAddress, noPublicIpCheck, deploymentMode,
                                deploymentConfigPath, statePath, quickStart) {
            if (!root.backend)
                return
            d.setupBusy = true
            d.setupBusyMessage = quickStart ? qsTr("Setting up your node…")
                                            : qsTr("Generating…")
            d.setupError = ""
            logos.watch(
                root.backend.generateConfig(outputPath, initialPeers, netPort, blendPort,
                                            httpAddr, externalAddress, noPublicIpCheck,
                                            deploymentMode, deploymentConfigPath, statePath),
                function(result) {
                    d.setupBusy = false
                    d.setupBusyMessage = ""
                    if (!result.success) {
                        if (!quickStart && root.backend.userConfig.length > 0) {
                            d.setupError = ""
                            d.loadPowAccounts(root.backend.userConfig)
                            d.loadKeystoreKeys(root.backend.userConfig)
                            onboardingView.configGenerated()
                            return
                        }
                        d.setupError = result.error
                        return
                    }

                    const resolved = (result.value !== undefined && result.value !== "")
                        ? result.value
                        : (outputPath !== "" ? outputPath
                                             : root.backend.generatedUserConfigPath)
                    root.backend.userConfig = resolved
                    root.backend.deploymentConfig =
                        (deploymentMode === 1 && deploymentConfigPath !== "")
                            ? deploymentConfigPath : ""
                    root.backend.useGeneratedConfig = true
                    d.loadPowAccounts(resolved)

                    if (quickStart) {
                        root.finished(true)
                        return
                    }
                    d.loadKeystoreKeys(resolved)
                    onboardingView.configGenerated()
                },
                function(error) {
                    d.setupBusy = false
                    d.setupBusyMessage = ""
                    d.setupError = error
                })
        }

        function savePowConfig(configJson) {
            if (!root.backend)
                return
            d.setupBusy = true
            d.setupBusyMessage = qsTr("Saving…")
            d.setupError = ""
            logos.watch(
                root.backend.powConfigure(d.powConfigPath, configJson),
                function(result) {
                    d.setupBusy = false
                    d.setupBusyMessage = ""
                    if (result.success)
                        onboardingView.powConfigured()
                    else
                        d.setupError = result.error
                },
                function(error) {
                    d.setupBusy = false
                    d.setupBusyMessage = ""
                    d.setupError = error
                })
        }
    }

    OnboardingView {
        id: onboardingView
        objectName: "onboardingView"
        anchors.fill: parent

        userConfigPath: root.backend ? root.backend.userConfig : ""
        powSection: root.backend ? root.backend.configPowSection : ({})
        deploymentConfigPath: root.backend ? root.backend.deploymentConfig : ""
        nodeKeystorePath: root.backend ? root.backend.nodeKeystorePath : ""
        keysBackedUp: !!root.backend && root.backend.keysBackedUp
        bootstrapPeers: root.backend ? root.backend.bootstrapPeers : []
        configExists: !!root.backend && root.backend.useGeneratedConfig
                      && root.backend.userConfig.length > 0
        canExit: root.canExit
        busy: d.setupBusy
        busyMessage: d.setupBusyMessage
        errorMessage: d.setupError

        onGenerateRequested: function(outputPath, initialPeers, netPort, blendPort, httpAddr,
                                      externalAddress, noPublicIpCheck, deploymentMode,
                                      deploymentConfigPath, statePath) {
            d.generateConfig(outputPath, initialPeers, netPort, blendPort, httpAddr,
                             externalAddress, noPublicIpCheck, deploymentMode,
                             deploymentConfigPath, statePath,
                             onboardingView.atWelcomeScreen)
        }

        onUserConfigPathSelected: function(path) {
            if (!root.backend) return
            root.backend.userConfig = path
            root.backend.useGeneratedConfig = false
            d.powConfigPath = path
            d.loadKeystoreKeys(path)
        }

        onDeploymentConfigPathSelected: function(path) {
            if (root.backend) root.backend.deploymentConfig = path
        }

        onPowConfigureRequested: function(configJson) { d.savePowConfig(configJson) }

        onBackupKeystoreRequested: function(destinationPath) {
            if (!root.backend) return
            d.setupError = ""
            logos.watch(
                root.backend.backupKeystore(destinationPath),
                function(result) {
                    if (result.success)
                        root.keystoreSaved(result.value)
                    else
                        d.setupError = result.error
                },
                function(error) { d.setupError = error })
        }

        onExitRequested: root.exitRequested()
        onFinished: function(startNode) { root.finished(startNode) }
    }
}
