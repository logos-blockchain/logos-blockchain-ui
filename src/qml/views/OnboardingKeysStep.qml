pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

// Step 3: the keystore, and the one step in the wizard that refuses to be
// skipped. Generating a config also generated every key the node will ever
// use, nothing can reissue them, and this is the single point in the flow where
// a user can lose something irreplaceable by clicking past it.
ColumnLayout {
    id: root

    // Rows { address, label } — every key in the keystore, not only the ones
    // the config wires to a job.
    property var keys: []
    property string keystorePath: ""
    // The keystore for this config is already saved, so the gate is satisfied
    // and the checkbox is redundant.
    property bool alreadyBackedUp: false
    property string errorMessage: ""
    readonly property bool acknowledged: root.alreadyBackedUp || savedCheckBox.checked

    signal downloadRequested(string destinationPath)

    spacing: Theme.spacing.medium

    LogosText {
        text: qsTr("Back up your node keys")
        color: Theme.palette.text
        font.pixelSize: OnboardingText.stepHeading
        font.weight: Theme.typography.weightBold
    }

    LogosNotice {
        Layout.fillWidth: true
        objectName: "keysShownOnceNotice"
        shown: !root.alreadyBackedUp
        severity: LogosNotice.Warning
        title: qsTr("One copy, on this machine")
        message: qsTr("Generating your config created a keystore of %n key(s), which control "
                      + "your node's identity, stake and rewards. It lives with this app's "
                      + "data — if that is lost, wiped or reinstalled, nothing can reissue "
                      + "these keys or what they hold. Keep a copy somewhere else.",
                      "", root.keys.length)
    }

    LogosNotice {
        Layout.fillWidth: true
        objectName: "keysAlreadyBackedUpNotice"
        shown: root.alreadyBackedUp
        severity: LogosNotice.Success
        title: qsTr("Keys saved")
        message: qsTr("The keystore for this config has already been backed up. You can save "
                      + "another copy if you want one.")
    }

    // ---- The keys ----------------------------------------------------------

    LogosFrame {
        Layout.fillWidth: true
        visible: root.keys.length > 0
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusMedium
        padding: Theme.spacing.medium

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            Repeater {
                model: root.keys

                delegate: RowLayout {
                    id: keyRow

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    LogosText {
                        Layout.preferredWidth: 180
                        text: keyRow.modelData.label || qsTr("Untitled key")
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                        elide: Text.ElideRight
                    }

                    LogosText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: keyRow.modelData.address || ""
                        color: Theme.palette.textSecondary
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.secondaryText
                        elide: Text.ElideRight
                    }

                    LogosCopyButton { value: keyRow.modelData.address || "" }
                }
            }
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: root.keys.length === 0
        text: qsTr("The keystore's contents could not be listed. That does not stop you "
                   + "backing it up — the file is what matters, and Download saves it.")
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    // ---- Backup ------------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        LogosButton {
            objectName: "keysDownloadButton"
            enabled: root.keystorePath.length > 0
            text: qsTr("Download keystore.yaml")
            onClicked: keystoreSaveDialog.open()
        }

        Item { Layout.fillWidth: true }
    }

    LogosCheckbox {
        id: savedCheckBox
        objectName: "keysAcknowledgeCheckbox"
        visible: !root.alreadyBackedUp
        text: qsTr("I've backed up my keys somewhere safe")
        font.pixelSize: Theme.typography.secondaryText
    }

    LogosNotice {
        objectName: "keysErrorNotice"
        Layout.fillWidth: true
        shown: root.errorMessage.length > 0
        severity: LogosNotice.Error
        title: qsTr("Backup failed")
        message: root.errorMessage
        actions: [
            LogosCopyButton { value: root.errorMessage }
        ]
    }

    Item { Layout.fillHeight: true }

    FileDialog {
        id: keystoreSaveDialog
        title: qsTr("Save a copy of your keystore")
        modality: Qt.NonModal
        fileMode: FileDialog.SaveFile
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        defaultSuffix: "yaml"
        nameFilters: [qsTr("Keystore files (*.yaml *.yml)"), qsTr("All files (*)")]
        onAccepted: root.downloadRequested(selectedFile)
    }
}
