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
            StyledAddressComboBox {
                id: balanceAddressCombo
                model: knownAddresses
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

                LogosButton {
                    Layout.fillWidth: true
                    enabled: false
                    padding: Theme.spacing.medium
                    contentItem: Text {
                        id: balanceResultText
                        width: parent.width
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    // Transfer funds card
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: transferCol.height + 2 * Theme.spacing.large
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
            spacing: Theme.spacing.small

            LogosText {
                text: qsTr("Transfer funds")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            StyledAddressComboBox {
                id: transferFromCombo
                model: knownAddresses
            }

            LogosTextField {
                id: transferToField
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                placeholderText: qsTr("To key (64 hex chars)")
            }

            LogosTextField {
                id: transferAmountField
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                placeholderText: qsTr("Amount")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: transferButton.implicitHeight
                spacing: Theme.spacing.large

                LogosButton {
                    id: transferButton
                    text: qsTr("Transfer")
                    Layout.alignment: Qt.AlignRight
                    onClicked: root.transferRequested(transferFromCombo.currentText.trim(), transferToField.text.trim(), transferAmountField.text)
                }

                LogosButton {
                    Layout.fillWidth: true
                    enabled: false
                    padding: Theme.spacing.medium
                    contentItem: Text {
                        id: transferResultText
                        width: parent.width
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.spacing.small
    }

    component StyledAddressComboBox: ComboBox {
        id: comboControl

        Layout.fillWidth: true
        padding: Theme.spacing.large
        editable: true
        font.pixelSize: Theme.typography.secondaryText

        background: Rectangle {
            color: Theme.palette.backgroundTertiary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1
        }
        indicator: LogosText {
            id: comboIndicator
            text: "▼"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            x: comboControl.width - width - Theme.spacing.small
            y: (comboControl.height - height) / 2
            visible: comboControl.count > 0
        }
        contentItem: Item {
            implicitWidth: 200
            implicitHeight: 30

            TextField {
                id: comboTextField
                anchors.fill: parent
                leftPadding: 0
                rightPadding: comboControl.count > 0 ? comboIndicator.width + Theme.spacing.small : Theme.spacing.small
                topPadding: 0
                bottomPadding: 0
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
                text: comboControl.editText
                onTextChanged: if (text !== comboControl.editText) comboControl.editText = text
                selectByMouse: true
                color: Theme.palette.text
                background: Item { }
            }
            MouseArea {
                anchors.fill: parent
                visible: comboControl.count > 0
                z: 1
                onPressed: {
                    comboControl.popup.visible ? comboControl.popup.close() : comboControl.popup.open()
                }
            }
        }
        delegate: ItemDelegate {
            id: comboDelegate
            width: comboControl.width
            contentItem: LogosText {
                width: parent.width
                height: contentHeight + Theme.spacing.large
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
                text: modelData
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: comboDelegate.highlighted ?
                           Theme.palette.backgroundTertiary :
                           Theme.palette.backgroundSecondary
            }
            highlighted: comboControl.highlightedIndex === index
        }
        popup: Popup {
            y: comboControl.height - 1
            width: comboControl.width
            height: contentItem.implicitHeight
            padding: 1

            onOpened: if (comboControl.count === 0) close()

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: comboControl.popup.visible ? comboControl.delegateModel : null
                ScrollIndicator.vertical: ScrollIndicator { }
                highlightFollowsCurrentItem: false
            }

            background: Rectangle {
                color: Theme.palette.backgroundSecondary
                border.color: Theme.palette.border
                border.width: 1
                radius: Theme.spacing.radiusLarge
            }
        }
    }
}
