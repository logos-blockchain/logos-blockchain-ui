import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

import "OnboardingPaths.js" as OnboardingPaths

import "infoContent.js" as InfoContent

// Step 2: which chain, and who to dial to find it.
ColumnLayout {
    id: root

    property bool busy: false
    property string errorMessage: ""
    property bool locked: false
    // Peers the build ships. Quick start uses these silently; Advanced has to
    // offer them too, or taking the longer route means starting from nothing.
    property var defaultPeers: []
    // Where the config that locked this step lives, so the notice can point at it.
    property string userConfigPath: ""
    readonly property int peerCount: d.peers().length
    readonly property bool needsDeployment: d.custom
                                            && customDeploymentField.text.trim().length === 0
    readonly property bool needsPeers: root.peerCount === 0
    readonly property bool valid: !root.needsDeployment && !root.needsPeers

    signal submitted(string outputPath, var initialPeers, int netPort, int blendPort,
                     string httpAddr, string externalAddress, bool noPublicIpCheck,
                     int deploymentMode, string deploymentConfigPath, string statePath)

    // Called by the host when setup opens, so a second run does not inherit
    // the first one's typing.
    function reset() {
        d.custom = false
        customDeploymentField.text = ""
        initialPeersArea.text = root.defaultPeers.join("\n")
    }

    function submit() {
        root.submitted("",
                       d.peers(),
                       0, 0,
                       "", "",
                       false,
                       d.custom ? 1 : 0,
                       customDeploymentField.text.trim(),
                       "")
    }

    Component.onCompleted: root.reset()
    onDefaultPeersChanged: {
        // Only while untouched — never clobber what the user typed.
        if (initialPeersArea.text.trim().length === 0)
            initialPeersArea.text = root.defaultPeers.join("\n")
    }

    QtObject {
        id: d
        property bool custom: false

        function peers() {
            return initialPeersArea.text
                .split("\n")
                .map(function(s) { return s.trim() })
                .filter(function(s) { return s.length > 0 })
        }
    }

    spacing: Theme.spacing.medium

    LogosText {
        text: qsTr("Network")
        color: Theme.palette.text
        font.pixelSize: OnboardingText.stepHeading
        font.weight: Theme.typography.weightBold
    }

    LogosNotice {
        objectName: "networkLockedNotice"
        Layout.fillWidth: true
        shown: root.locked
        severity: LogosNotice.Info
        title: qsTr("These settings are already written")
        message: root.userConfigPath.length > 0
            ? qsTr("Your node config exists, and it cannot be generated a second time, so "
                   + "nothing typed here would reach it. To change the peers or the "
                   + "deployment, edit the file directly:\n\n%1").arg(root.userConfigPath)
            : qsTr("Your node config exists, and it cannot be generated a second time, so "
                   + "nothing typed here would reach it. Settings shows you where the file is.")
    }

    // ---- Deployment --------------------------------------------------------

    OnboardingChoiceCard {
        objectName: "networkDefaultCard"
        Layout.fillWidth: true
        enabled: !root.locked
        title: qsTr("Default (public testnet)")
        badge: qsTr("Recommended")
        description: qsTr("Uses the deployment config this build ships with.")
        selected: !d.custom
        onPicked: d.custom = false
    }

    OnboardingChoiceCard {
        objectName: "networkCustomCard"
        Layout.fillWidth: true
        enabled: !root.locked
        title: qsTr("Custom deployment file")
        description: qsTr("Supply your own deployment YAML (private net or a pinned genesis).")
        selected: d.custom
        onPicked: d.custom = true
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        visible: d.custom
        spacing: Theme.spacing.medium

        LogosText {
            Layout.preferredWidth: 110
            text: qsTr("Deployment")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        LogosTextField {
            id: customDeploymentField
            objectName: "networkDeploymentPathField"
            Layout.fillWidth: true
            readOnly: root.locked
            placeholderText: qsTr("Choose or paste a deployment config path")
        }

        LogosButton {
            visible: !root.locked
            text: qsTr("Browse")
            onClicked: deploymentConfigFileDialog.open()
        }
    }

    // ---- Bootstrap peers ---------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Bootstrap peers")
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightMedium
        }

        Item { Layout.fillWidth: true }

        LogosInfoButton {
            title: qsTr("Bootstrap peers")
            dialogContentItem: InfoSections { info: InfoContent.bootstrapPeers }
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
        text: qsTr("The node dials these on start to find the chain (one multiaddr per "
                   + "line). Required — the deployment above does not provide them.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: 90

        LogosTextArea {
            id: initialPeersArea
            objectName: "networkPeersField"
            readOnly: root.locked
            focusBorderColor: Theme.palette.overlayOrange
            placeholderText: qsTr("/ip4/…/udp/3000/quic-v1/p2p/12D3KooW…")
            font.family: Theme.typography.mono
            font.pixelSize: Theme.typography.secondaryText
        }
    }

    LogosText {
        Layout.fillWidth: true
        visible: !root.locked
        text: qsTr("Generating writes your config. These settings cannot be changed "
                   + "afterwards without editing the file by hand.")
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosNotice {
        objectName: "networkErrorNotice"
        Layout.fillWidth: true
        shown: root.errorMessage.length > 0
        severity: LogosNotice.Error
        title: qsTr("Could not generate a config")
        message: root.errorMessage
        actions: [
            LogosCopyButton { value: root.errorMessage }
        ]
    }

    Item { Layout.fillHeight: true }

    FileDialog {
        id: deploymentConfigFileDialog
        modality: Qt.NonModal
        nameFilters: [qsTr("YAML files (*.yaml *.yml)"), qsTr("All files (*)")]
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: customDeploymentField.text = OnboardingPaths.toLocalPath(selectedFile)
    }
}
