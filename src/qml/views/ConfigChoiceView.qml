import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ColumnLayout {
    id: root

    property string userConfigPath: ""
    property string deploymentConfigPath: ""
    property string generatedUserConfigPath: ""

    property bool generateResultSuccess: false
    property string generateResultMessage: ""

    // PoW step, filled in by the host once the config exists.
    property var powAccounts: []
    property bool powBusy: false
    property bool powResultSuccess: false
    property string powResultMessage: ""

    signal generateRequested(string outputPath, var initialPeers, int netPort, int blendPort, string httpAddr, string externalAddress, bool noPublicIpCheck, int deploymentMode, string deploymentConfigPath, string statePath)
    signal setPathToConfigsRequested()
    signal userConfigPathSelected(string path)
    signal deploymentConfigPathSelected(string path)
    signal powConfirmRequested(string configJson)

    QtObject {
        id: d
        property int selectedOption: 0
        readonly property bool hasContent: selectedOption >= 1 && selectedOption <= 3
    }

    // Switch to the "set path to config" sub-view. Used after the PoW step to
    // land on the resolved-config-path screen, from which the user continues to
    // start the node.
    function showSetConfigPath() { d.selectedOption = 2 }

    // Switch to the PoW sub-view. Generating a config is what makes this
    // reachable: the settings are edited into that file, and the node reads them
    // only at start, so this is the last moment before they take effect.
    function showPowConfig() { d.selectedOption = 3 }

    spacing: Theme.spacing.large

    LogosText {
        Layout.alignment: Qt.AlignLeft
        font.bold: true
        font.pixelSize: Theme.typography.primaryText
        text: qsTr("Choose how to set up your node config")
    }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        Layout.topMargin: -Theme.spacing.small
        text: qsTr("Generate a new config, or set paths to your existing config files.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.minimumWidth: 0
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.large

        LogosButton {
            objectName: "chooserGenerateButton"
            text: qsTr("Generate config")
            Layout.preferredHeight: 50
            Layout.fillWidth: true
            onClicked: d.selectedOption = 1
        }

        LogosButton {
            objectName: "chooserSetPathButton"
            text: qsTr("Set path to config")
            Layout.preferredHeight: 50
            Layout.fillWidth: true
            onClicked: d.selectedOption = 2
        }
    }

    Loader {
        id: contentLoader
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: d.hasContent
        active: d.hasContent
        sourceComponent: {
            switch (d.selectedOption) {
            case 1: return generateConfigComponent
            case 2: return setConfigPathComponent
            case 3: return powConfigComponent
            default: return null
            }
        }
    }

    Item {
        Layout.fillHeight: true
        visible: !d.hasContent
    }

    Component {
        id: generateConfigComponent
        ColumnLayout {
            spacing: Theme.spacing.medium
            GenerateConfigView {
                generatedUserConfigPath: root.generatedUserConfigPath
                resultSuccess: root.generateResultSuccess
                resultMessage: root.generateResultMessage
                Layout.fillWidth: true
                onGenerateRequested: function(outputPath, initialPeers, netPort, blendPort,
                                              httpAddr, externalAddress, noPublicIpCheck,
                                              deploymentMode, deploymentConfigPath, statePath) {
                    root.generateRequested(outputPath, initialPeers, netPort, blendPort,
                                           httpAddr, externalAddress, noPublicIpCheck,
                                           deploymentMode, deploymentConfigPath, statePath)
                }
            }
        }
    }

    Component {
        id: powConfigComponent
        PowConfigView {
            objectName: "powConfigView"
            accounts: root.powAccounts
            busy: root.powBusy
            resultSuccess: root.powResultSuccess
            resultMessage: root.powResultMessage
            onConfirmRequested: function(configJson) { root.powConfirmRequested(configJson) }
        }
    }

    Component {
        id: setConfigPathComponent
        SetConfigPathView {
            userConfigPath: root.userConfigPath
            deploymentConfigPath: root.deploymentConfigPath
            onUserConfigPathSelected: function(path) { root.userConfigPathSelected(path) }
            onDeploymentConfigPathSelected: function(path) { root.deploymentConfigPathSelected(path) }
            onSetPathToConfigsRequested: root.setPathToConfigsRequested()
        }
    }
}
