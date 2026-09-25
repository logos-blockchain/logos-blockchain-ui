import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

import "OnboardingPaths.js" as OnboardingPaths

// Step 1: where the config comes from. The only question on this screen,
// because the answer changes which screens follow it.
ColumnLayout {
    id: root

    // "generate", "existing", or empty until answered.
    property string mode: ""
    property string userConfigPath: ""
    property string deploymentConfigPath: ""
    property string errorMessage: ""

    signal modePicked(string mode)
    signal userConfigPathSelected(string path)
    signal deploymentConfigPathSelected(string path)

    spacing: Theme.spacing.medium

    LogosText {
        text: qsTr("How do you want to start?")
        color: Theme.palette.text
        font.pixelSize: OnboardingText.stepHeading
        font.weight: Theme.typography.weightBold
    }

    // Stacked, not side by side: these are read before they are chosen between,
    // and a column is the order the eye already follows.
    OnboardingChoiceCard {
        objectName: "setupGenerateCard"
        Layout.fillWidth: true
        title: qsTr("Generate a new node")
        badge: qsTr("Recommended")
        description: qsTr("Create a fresh config and keystore. Best if this is your first node.")
        selected: root.mode === "generate"
        onPicked: root.modePicked("generate")
    }

    OnboardingChoiceCard {
        objectName: "setupExistingCard"
        Layout.fillWidth: true
        title: qsTr("Use an existing config")
        description: qsTr("Point at a user config you already have (e.g. moving to a new "
                          + "machine). Nothing in it is rewritten.")
        selected: root.mode === "existing"
        onPicked: root.modePicked("existing")
    }

    // Only the existing route needs paths, and asking for them before the route
    // is chosen would put two unrelated questions on one screen.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        visible: root.mode === "existing"
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Point to your files")
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightMedium
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            LogosText {
                Layout.preferredWidth: 110
                text: qsTr("User config")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosTextField {
                id: userConfigField
                objectName: "setupUserConfigField"
                Layout.fillWidth: true
                placeholderText: qsTr("~/.logos/node/user_config.yaml")
                Component.onCompleted: text = root.userConfigPath
                onTextChanged: root.userConfigPathSelected(text.trim())
            }

            LogosButton {
                objectName: "setupBrowseUserConfigButton"
                text: qsTr("Browse")
                onClicked: userConfigFileDialog.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            LogosText {
                Layout.preferredWidth: 110
                text: qsTr("Deployment")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosTextField {
                id: deploymentField
                objectName: "setupDeploymentField"
                Layout.fillWidth: true
                placeholderText: qsTr("Optional — defaults to the public testnet")
                Component.onCompleted: text = root.deploymentConfigPath
                onTextChanged: root.deploymentConfigPathSelected(text.trim())
            }

            LogosButton {
                objectName: "setupBrowseDeploymentButton"
                text: qsTr("Browse")
                onClicked: deploymentConfigFileDialog.open()
            }
        }

        LogosText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: qsTr("Your keys stay where they are — the node reads them from beside your "
                       + "config.")
            color: Theme.palette.textTertiary
            font.pixelSize: OnboardingText.fieldHint
            wrapMode: Text.WordWrap
        }
    }

    LogosNotice {
        objectName: "setupErrorNotice"
        Layout.fillWidth: true
        shown: root.errorMessage.length > 0
        severity: LogosNotice.Error
        title: qsTr("Setup failed")
        message: root.errorMessage
        actions: [
            LogosCopyButton { value: root.errorMessage }
        ]
    }

    Item { Layout.fillHeight: true }

    FileDialog {
        id: userConfigFileDialog
        modality: Qt.NonModal
        title: qsTr("Select your user config")
        currentFolder: OnboardingPaths.toFolderUrl(userConfigField.text)
                       || StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        nameFilters: [qsTr("YAML files (*.yaml *.yml)"), qsTr("All files (*)")]
        onAccepted: userConfigField.text = OnboardingPaths.toLocalPath(selectedFile)
    }

    FileDialog {
        id: deploymentConfigFileDialog
        modality: Qt.NonModal
        title: qsTr("Select your deployment config")
        currentFolder: OnboardingPaths.toFolderUrl(deploymentField.text)
                       || StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        nameFilters: [qsTr("YAML files (*.yaml *.yml)"), qsTr("All files (*)")]
        onAccepted: deploymentField.text = OnboardingPaths.toLocalPath(selectedFile)
    }
}
