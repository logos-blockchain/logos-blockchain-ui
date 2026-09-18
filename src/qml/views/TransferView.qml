import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units

// Transfer funds panel. Extracted from the former WalletView.
ColumnLayout {
    id: root

    // Rows, not the remoted model: the replica lands count-first, and a combo's
    // currentValue reads at currentIndex — so a quick Send could transfer from
    // an empty key. A QVariantList lands whole.
    required property var accountRows

    signal transferRequested(string fromKeyHex, string toKeyHex, string amount)
    signal copyToClipboard(string text)

    // The selected source's balance, for the availability check below. Reading
    // the row rather than currentValue: currentValue is the address.
    readonly property var fromRow:
        transferFromCombo.currentIndex >= 0
        && transferFromCombo.currentIndex < accountRows.length
            ? accountRows[transferFromCombo.currentIndex] : null
    readonly property string fromBalance: fromRow ? (fromRow.balance || "") : ""

    readonly property string amountLepta:
        Units.toLepta(Units.normalizeInput(transferAmountField.text))
    // NaN when either side is not a figure — an unfetched balance cannot say
    // anything about affordability, so it must not read as "insufficient".
    readonly property bool overBalance:
        Units.compareLepta(amountLepta, fromBalance) > 0

    property string resultHash: ""
    property string resultError: ""

    function setTransferHash(hash) {
        root.resultHash = hash
        root.resultError = ""
    }

    function setTransferError(message) {
        root.resultError = message
        root.resultHash = ""
    }

    spacing: Theme.spacing.large

    // No container of its own — WalletView provides the page surface. The form's
    // rows sit directly in the root layout.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        FieldLabel { text: qsTr("From") }

        LogosComboBox {
            id: transferFromCombo
            Layout.fillWidth: true
            implicitHeight: 40
            background: Rectangle {
                radius: Theme.spacing.radiusSmall
                color: Theme.palette.backgroundSecondary
                border.width: 1
                border.color: transferFromCombo.activeFocus
                              ? Theme.palette.overlayOrange
                              : Theme.palette.backgroundElevated
            }
            model: root.accountRows
            textRole: "label"
            valueRole: "address"
            placeholderText: qsTr("From account")
            editable: false

            delegate: LogosItemDelegate {
                required property var modelData
                required property int index
                width: transferFromCombo.width
                implicitHeight: Math.max(
                    36, implicitContentHeight + topPadding + bottomPadding)
                highlighted: transferFromCombo.highlightedIndex === index
                contentItem: AccountSummary {
                    keyName: modelData.name || ""
                    roleLabel: modelData.roleLabel || ""
                    address: modelData.address || ""
                    balance: modelData.balance || ""
                }
            }
        }

        FieldLabel { text: qsTr("To"); Layout.topMargin: Theme.spacing.small }

        LogosTextField {
            id: transferToField
            Layout.fillWidth: true
            placeholderText: qsTr("Recipient key — 64 hex characters")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.small
            FieldLabel { text: qsTr("Amount (LGO)") }
            LogosText {
                Layout.alignment: Qt.AlignRight
                visible: text.length > 0
                text: Units.format(root.fromBalance).length > 0
                      ? qsTr("Available: %1").arg(Units.format(root.fromBalance)) : ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
        }

        LogosTextField {
            id: transferAmountField
            Layout.fillWidth: true
            placeholderText: qsTr("0.00")
            validator: RegularExpressionValidator {
                regularExpression: Units.inputRegExp(Qt.locale())
            }
        }

        LogosText {
            Layout.fillWidth: true
            visible: root.overBalance
            text: qsTr("More than this account holds.")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.medium
            spacing: Theme.spacing.small

            LogosButton {
                id: transferButton
                Layout.alignment: Qt.AlignTop
                text: qsTr("Send")
                enabled: String(transferFromCombo.currentValue || "").trim().length > 0
                         && transferToField.text.trim().length > 0
                         && root.amountLepta.length > 0
                         && !root.overBalance
                // Canonical LOGOS; the backend scales it to lepta.
                onClicked: root.transferRequested(
                    String(transferFromCombo.currentValue || "").trim(),
                    transferToField.text.trim(),
                    Units.normalizeInput(transferAmountField.text))
            }

        }

        LogosNotice {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.medium

            readonly property bool sent: root.resultHash.length > 0

            severity: sent ? LogosNotice.Success : LogosNotice.Error
            title: sent ? qsTr("Transaction sent") : qsTr("Transfer failed")
            message: sent ? root.resultHash : root.resultError
            shown: sent || root.resultError.length > 0
            closable: false

            actions: [
                LogosCopyButton {
                    visible: root.resultHash.length > 0
                    value: root.resultHash
                }
            ]
        }
    }

    Item { Layout.fillHeight: true }

    component FieldLabel: LogosText {
        Layout.fillWidth: true
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
    }
}
