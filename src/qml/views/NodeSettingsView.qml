import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

import "../controls"
import "infoContent.js" as InfoContent

// Node settings, one card per concern.
ColumnLayout {
    id: root

    // --- Public API ---
    property string userConfig: ""
    property string deploymentConfig: ""
    property bool useGeneratedConfig: false
    // The chooser is not reachable while the node is up: changing config under
    // a running node would leave the two disagreeing.
    property bool canChange: true
    // Whether the node is currently claiming mined rewards on its own. A
    // RUNTIME flag, not a stored setting — see the card below.
    property bool autoClaimRunning: false
    property bool nodeRunning: false
    // Where the node keeps db/, state/ and logs/. Empty when no config is set
    // or the node has not run yet.
    property string nodeDataDir: ""
    // The keystore, or empty when there is none for this config yet.
    property string nodeKeystorePath: ""
    property bool keysBackedUp: false
    // Why the last backup failed, or empty. Successes are announced by the
    // host as a toast rather than kept here.
    property string backupError: ""

    signal backupKeystoreRequested(string destinationPath)

    spacing: Theme.spacing.large

    signal changeConfigRequested()
    signal autoClaimToggled(bool enabled)


    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("Node")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosInfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    title: qsTr("Node config")
                    dialogContentItem: InfoSections { info: InfoContent.nodeConfig }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("User Config")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                // Copies the full path, not the elided display string.
                LogosCopyButton {
                    visible: root.userConfig.length > 0
                    value: root.userConfig
                }
            }

            LogosText {
                Layout.fillWidth: true
                text: (root.userConfig || qsTr("No file selected"))
                      + (root.useGeneratedConfig ? " " + qsTr("(Generated)") : "")
                color: Theme.palette.textTertiary
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                elide: Text.ElideMiddle
            }

            RowLayout {
                Layout.topMargin: Theme.spacing.small
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("Deployment Config")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosCopyButton {
                    visible: root.deploymentConfig.length > 0
                    value: root.deploymentConfig
                }
            }

            LogosText {
                Layout.fillWidth: true
                text: root.useGeneratedConfig && root.deploymentConfig
                          ? root.deploymentConfig
                          : root.useGeneratedConfig
                              ? qsTr("Default")
                              : (root.deploymentConfig || qsTr("No file selected"))
                color: Theme.palette.textTertiary
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                elide: Text.ElideMiddle
            }

            LogosButton {
                objectName: "changeConfigButton"
                Layout.topMargin: Theme.spacing.medium
                Layout.alignment: Qt.AlignRight
                enabled: root.canChange
                text: qsTr("Change config")
                onClicked: root.changeConfigRequested()
            }
        }
    }

    // ---- Back up your keys ----
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("Back up your keys")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                LogosBadge {
                    objectName: "keysBackedUpBadge"
                    visible: root.keysBackedUp
                    text: qsTr("Done")
                    color: Theme.palette.success
                }

                Item { Layout.fillWidth: true }
            }

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Your keystore holds the keys to your accounts. It is the one file "
                           + "nothing else can replace — lose it and the rewards those accounts "
                           + "hold are gone with it. Save a copy somewhere safe, away from this "
                           + "machine, and you can recover the accounts even if everything here "
                           + "is lost.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            HashRow {
                Layout.fillHeight: false
                visible: root.nodeKeystorePath.length > 0
                label: qsTr("Keystore")
                labelWidth: 72
                value: root.nodeKeystorePath
            }

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.nodeKeystorePath.length === 0
                text: qsTr("No keystore found yet — it appears once a config is set and the "
                           + "node has run at least once.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosButton {
                objectName: "backupKeystoreButton"
                Layout.topMargin: Theme.spacing.small
                Layout.alignment: Qt.AlignRight
                variant: LogosButton.Variant.Primary
                enabled: root.nodeKeystorePath.length > 0
                text: qsTr("Download keystore.yaml")
                onClicked: keystoreSaveDialog.open()
            }

            LogosNotice {
                Layout.fillWidth: true
                objectName: "backupResultNotice"
                shown: root.backupError.length > 0
                severity: LogosNotice.Error
                title: qsTr("Backup failed")
                message: root.backupError
                closable: true
                onDismissed: root.backupError = ""
                actions: [
                    LogosCopyButton { value: root.backupError }
                ]
            }
        }
    }

    // ---- Mining ----
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.bottomMargin: Theme.spacing.small
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("Mining")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosInfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    title: qsTr("Auto-claim")
                    dialogContentItem: InfoSections { info: InfoContent.autoClaim }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("Auto-claim")
                    font.pixelSize: Theme.typography.primaryText
                }
                LogosBadge {
                    objectName: "autoClaimRecommendedBadge"
                    text: qsTr("Recommended")
                    color: Theme.palette.success
                }

                Item { Layout.fillWidth: true }

                LogosSwitch {
                    objectName: "autoClaimSwitch"
                    checked: root.autoClaimRunning
                    enabled: root.nodeRunning
                    onToggled: root.autoClaimToggled(checked)
                }
            }

            LogosText {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                wrapMode: Text.WordWrap
                text: qsTr("The rest of mining — how many threads the search uses, which "
                           + "accounts auto-claim pays and the balance it stops at — lives in "
                           + "the config file, under pow. Copy its path from the Node card "
                           + "then restart the node.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }

    // ---- Destructive ----
    // A path and instructions, not a button.
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: Theme.palette.error
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            LogosText {
                Layout.bottomMargin: Theme.spacing.small
                text: qsTr("Reset the database")
                color: Theme.palette.text
                font.pixelSize: Theme.typography.panelTitleText
                font.weight: Theme.typography.weightMedium
            }

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("If the node is stuck or will not start, its database may be at "
                           + "fault. Stop the node, delete the folder below, then start it "
                           + "again — it will re-sync the chain from its peers. Your keys and "
                           + "config files are untouched.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            HashRow {
                Layout.fillHeight: false
                visible: root.nodeDataDir.length > 0
                label: qsTr("Database")
                labelWidth: 72
                value: root.nodeDataDir
            }

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.nodeDataDir.length === 0
                text: qsTr("No database found yet — it appears once a config is set and the "
                           + "node has run at least once.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }


    FileDialog {
        id: keystoreSaveDialog
        title: qsTr("Save a copy of your keystore")
        modality: Qt.NonModal
        fileMode: FileDialog.SaveFile
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        defaultSuffix: "yaml"
        nameFilters: [qsTr("Keystore files (*.yaml *.yml)"), qsTr("All files (*)")]
        onAccepted: root.backupKeystoreRequested(selectedFile)
    }

}
