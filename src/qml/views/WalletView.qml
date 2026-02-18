import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ColumnLayout {
    id: root

    // list of known wallet addresses for Get balance dropdown
    property var knownAddresses: []

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
        implicitHeight: balanceCol.implicitHeight + 2 * Theme.spacing.large
        Layout.preferredHeight: implicitHeight
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: balanceCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.large

            LogosText {
                text: qsTr("Get balance")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            // Dropdown of known addresses, or type a custom address
            ComboBox {
                id: balanceAddressCombo
                Layout.fillWidth: true
                editable: true
                model: knownAddresses
                font.pixelSize: Theme.typography.secondaryText
                placeholderText: qsTr("Select or enter wallet address (64 hex chars)")
                onActivated: function(index) {
                    if (index >= 0 && index < knownAddresses.length)
                        currentText = knownAddresses[index]
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: balanceButton.implicitHeight
                spacing: Theme.spacing.large

                LogosButton {
                    id: balanceButton
                    text: qsTr("Get balance")
                    onClicked: root.getBalanceRequested(balanceAddressCombo.currentText.trim())
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: balanceResultText.height + 2 * Theme.spacing.large
                    color: Theme.palette.backgroundSecondary
                    radius: Theme.spacing.radiusXlarge
                    border.color: Theme.palette.border
                    border.width: 1
                    LogosText {
                        id: balanceResultText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacing.large
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }
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
                id: transferFromField
                placeholderText: qsTr("From key (64 hex chars)")
            }

            CustomTextFeild {
                id: transferToField
                placeholderText: qsTr("To key (64 hex chars)")
            }

            CustomTextFeild {
                id: transferAmountField
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
