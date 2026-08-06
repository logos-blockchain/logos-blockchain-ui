import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import Logos.Theme
import Logos.Controls

ColumnLayout {
    id: root

    property string userConfigPath: ""
    property string deploymentConfigPath: ""

    signal userConfigPathSelected(string path)
    signal deploymentConfigPathSelected(string path)
    signal setPathToConfigsRequested()

    spacing: Theme.spacing.medium

    LogosText {
        Layout.alignment: Qt.AlignLeft
        text: qsTr("Select your config files, then continue to the node.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("User Config: ")
            font.bold: true
        }
        LogosText {
            Layout.fillWidth: true
            text: root.userConfigPath || qsTr("No file selected")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            wrapMode: Text.WordWrap
        }
        LogosButton {
            text: qsTr("Browse")
            onClicked: userConfigFileDialog.open()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Deployment Config: ")
            font.bold: true
        }
        LogosText {
            Layout.fillWidth: true
            // Empty deployment config is not an error: the module reads it as a
            // null deployment and falls back to its built-in default network.
            text: root.deploymentConfigPath || qsTr("Default (built-in network)")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            wrapMode: Text.WordWrap
        }
        // Clearing the deployment config resets it to the built-in default. This
        // is the only way back to the default once a custom file has been picked
        // (or restored from a previous session), so a stale path can't silently
        // ride along into start().
        LogosButton {
            text: qsTr("Use default")
            visible: !!root.deploymentConfigPath
            onClicked: root.deploymentConfigPathSelected("")
        }
        LogosButton {
            text: qsTr("Browse")
            onClicked: deploymentConfigFileDialog.open()
        }
    }

    LogosButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 50
        text: qsTr("Continue")
        enabled: !!root.userConfigPath
        onClicked: root.setPathToConfigsRequested()
    }

    FileDialog {
        id: userConfigFileDialog
        modality: Qt.NonModal
        nameFilters: ["YAML files (*.yaml *.yml)", "All files (*)"]
        onAccepted: root.userConfigPathSelected(selectedFile)
    }

    FileDialog {
        id: deploymentConfigFileDialog
        modality: Qt.NonModal
        nameFilters: ["YAML files (*.yaml *.yml)", "All files (*)"]
        onAccepted: root.deploymentConfigPathSelected(selectedFile)
    }
}
