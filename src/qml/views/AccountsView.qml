import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Accounts panel: the list of known wallet addresses with per-account
// balance refresh and copy. Extracted from the former WalletView.
ColumnLayout {
    id: root

    required property var accountsModel

    signal getBalanceRequested(string addressHex)
    signal refreshAccountsRequested()
    signal copyToClipboard(string text)

    function setBalanceResult(addressHex, success, errorMessage) {
        var next = Object.assign({}, d.pending)
        delete next[addressHex]
        d.pending = next

        d.errorAddress = success ? "" : addressHex
        d.errorMessage = success ? "" : (errorMessage || "")
    }

    QtObject {
        id: d
        property var pending: ({})
        property string errorAddress: ""
        property string errorMessage: ""

        function markPending(addressHex) {
            var next = Object.assign({}, d.pending)
            next[addressHex] = true
            d.pending = next
        }
    }

    spacing: Theme.spacing.large

    LogosFrame {
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.large

            RowLayout {
                Layout.fillWidth: true
                LogosText {
                    text: qsTr("Accounts")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    text: qsTr("Refresh")
                    padding: Theme.spacing.small
                    onClicked: root.refreshAccountsRequested()
                }
                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Your wallet addresses and balances. Press Refresh to fetch the latest known addresses and their balances from the running node.")
                }
            }

            LogosText {
                text: qsTr("Start node to see accounts here.")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: balanceListView.count === 0
            }

            LogosListView {
                id: balanceListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.accountsModel
                spacing: Theme.spacing.small

                delegate: AccountDelegate {
                    balanceError: d.errorAddress === model.address ? d.errorMessage : ""
                    refreshing: !!d.pending[model.address]
                    onGetBalanceRequested: (addr) => {
                        d.markPending(addr)
                        root.getBalanceRequested(addr)
                    }
                    onCopyRequested: (text) => root.copyToClipboard(text)
                }
            }
        }
    }
}
