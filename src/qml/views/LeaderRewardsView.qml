import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Leader rewards panel. Extracted from the former WalletView.
ColumnLayout {
    id: root

    signal claimLeaderRewardsRequested()
    signal copyToClipboard(string text)

    function setLeaderClaimResult(text) {
        leaderClaimResultText.text = text
    }

    spacing: Theme.spacing.large

    Rectangle {
        id: leaderRewardsRect

        Layout.fillWidth: true
        Layout.preferredHeight: leaderRewardsCol.height + 2 * Theme.spacing.large
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: leaderRewardsCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.small

            LogosText {
                text: qsTr("Leader rewards")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true

                LogosButton {
                    id: leaderClaimButton
                    Layout.preferredWidth: 140
                    text: qsTr("Claim")
                    onClicked: root.claimLeaderRewardsRequested()
                }

                LogosButton {
                    Layout.fillWidth: true
                    enabled: true
                    padding: Theme.spacing.small
                    contentItem: RowLayout {
                        width: parent.width
                        anchors.centerIn: parent
                        LogosText {
                            id: leaderClaimResultText
                            Layout.fillWidth: true
                            color: Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                            font.weight: Theme.typography.weightMedium
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }
                        LogosCopyButton {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredHeight: 40
                            Layout.preferredWidth: 40
                            onCopyText: root.copyToClipboard(leaderClaimResultText.text)
                            visible: leaderClaimResultText.text
                        }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
