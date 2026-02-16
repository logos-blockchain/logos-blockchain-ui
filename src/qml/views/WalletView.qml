import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ColumnLayout {
    id: root

    // --- Public API ---
    signal getBalanceRequested(string addressHex)
    signal transferRequested(string fromKeyHex, string toKeyHex, string amount)

    // Call these from the parent to display results
    function setBalanceResult(text) {
        balanceResultText.text = text
    }
    function setTransferResult(text) {
        transferResultText.text = text
    }

    spacing: Theme.spacing.medium

    // Get balance card
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: balanceCol.implicitHeight
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: balanceCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.large

            LogosText {
                text: qsTr("Get balance")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            CustomTextFeild {
                id: balanceAddressField
                placeholderText: qsTr("Wallet address (64 hex chars)")
            }

            LogosButton {
                text: qsTr("Get balance")
                Layout.alignment: Qt.AlignRight
                onClicked: root.getBalanceRequested(balanceAddressField.text)
            }

            LogosText {
                id: balanceResultText
                Layout.fillWidth: true
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                wrapMode: Text.WordWrap
            }
        }
    }

    // Transfer funds card
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: transferCol.height
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: transferCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.large

            LogosText {
                text: qsTr("Transfer funds")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            CustomTextFeild {
                placeholderText: qsTr("From key (64 hex chars)")
            }

            CustomTextFeild {
                id: transferToField
                placeholderText: qsTr("To key (64 hex chars)")
            }

            CustomTextFeild {
                placeholderText: qsTr("Amount")
            }

            LogosButton {
                text: qsTr("Transfer")
                Layout.alignment: Qt.AlignRight
                onClicked: root.transferRequested(transferFromField.text, transferToField.text, transferAmountField.text)
            }

            LogosText {
                id: transferResultText
                Layout.fillWidth: true
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                wrapMode: Text.WordWrap
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.spacing.small
    }

    component CustomTextFeild: TextField {
        id: textField
        Layout.fillWidth: true
        placeholderText: qsTr("From key (64 hex chars)")
        font.pixelSize: Theme.typography.secondaryText

        background: Rectangle {
            radius: Theme.spacing.radiusSmall
            color: Theme.palette.backgroundSecondary
            border.color: textField.activeFocus ?
                              Theme.palette.overlayOrange :
                              Theme.palette.backgroundElevated
        }
    }
}
