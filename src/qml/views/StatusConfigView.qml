import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ColumnLayout {
    id: root

    // --- Public API ---
    required property string statusText
    required property color  statusColor
    required property string userConfig
    required property string deploymentConfig
    required property bool   useGeneratedConfig
    required property bool   canStart
    required property bool   isRunning

    signal startRequested()
    signal stopRequested()
    signal changeConfigRequested()

    spacing: Theme.spacing.large

    // Status Card
    Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: parent.width * 0.9
        Layout.preferredHeight: implicitHeight
        implicitHeight: statusContent.implicitHeight + 2 * Theme.spacing.large
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: statusContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.medium

            LogosText {
                Layout.alignment: Qt.AlignLeft
                font.bold: true
                text: root.statusText
                color: root.statusColor
            }

            LogosText {
                Layout.alignment: Qt.AlignLeft
                Layout.topMargin: -Theme.spacing.medium
                text: qsTr("Mainnet - chain ID 1")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            LogosButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width
                Layout.preferredHeight: 50
                enabled: root.canStart
                text: root.isRunning ? qsTr("Stop Node") : qsTr("Start Node")
                onClicked: root.isRunning ? root.stopRequested() : root.startRequested()
            }
        }
    }

    // Config Card
    Rectangle {
        Layout.preferredWidth: parent.width * 0.9
        Layout.preferredHeight: implicitHeight
        implicitHeight: contentLayout.implicitHeight + 2 * Theme.spacing.large

        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: contentLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.medium

            LogosText {
                text: qsTr("Config")
                font.bold: true
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
                    text: (root.userConfig || qsTr("No file selected")) +
                          (root.useGeneratedConfig ? " " + qsTr("(Generated)") : "")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: -Theme.spacing.small
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Deployment Config: ")
                    font.bold: true
                }
                LogosText {
                    Layout.fillWidth: true
                    text: (root.useGeneratedConfig && root.deploymentConfig ? root.deploymentConfig :
                           root.useGeneratedConfig ? qsTr("Devnet (default)") :
                           (root.deploymentConfig || qsTr("No file selected")))
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    wrapMode: Text.WordWrap
                }
            }

            LogosButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                text: qsTr("Change")
                onClicked: root.changeConfigRequested()
            }
        }
    }

    Item { Layout.fillHeight: true }
}
