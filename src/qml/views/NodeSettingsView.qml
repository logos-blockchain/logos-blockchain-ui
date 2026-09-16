import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Node settings: which config files the node runs from, and the route back to
// the chooser that produces them.
//
// This is the config block that used to sit at the foot of the node card. The
// design moves node configuration off the dashboard and into Settings; the
// dashboard is for what the node is *doing*, not how it was set up.
ColumnLayout {
    id: root

    // --- Public API ---
    property string userConfig: ""
    property string deploymentConfig: ""
    property bool useGeneratedConfig: false
    // The chooser is not reachable while the node is up: changing config under
    // a running node would leave the two disagreeing.
    property bool canChange: true

    signal changeConfigRequested()

    spacing: Theme.spacing.large

    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            LogosText {
                text: qsTr("Node config")
                color: Theme.palette.text
                font.pixelSize: Theme.typography.panelTitleText
                font.weight: Theme.typography.weightMedium
            }

            LogosText {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacing.small
                text: qsTr("The files the node is started from. Change them from the chooser.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
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
                // Load-bearing: the doc-test's first action clicks this to
                // reach the config chooser (doctests/blockchain-ui-app.test.yaml).
                objectName: "changeConfigButton"
                Layout.topMargin: Theme.spacing.medium
                Layout.alignment: Qt.AlignRight
                enabled: root.canChange
                text: qsTr("Change")
                onClicked: root.changeConfigRequested()
            }
        }
    }

    Item { Layout.fillHeight: true }
}
