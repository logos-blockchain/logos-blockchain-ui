import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Wallet section: Accounts, Transfer and Channel Deposit behind a left menu.
RowLayout {
    id: root

    property var accountsModel: null
    property var accountRows: []
    property bool nodeRunning: false

    // ---- Requests out (the host orchestrates these) ----
    signal refreshAccountsRequested()
    signal transferRequested(string fromKeyHex, string toKeyHex, string amount)
    signal getNotesRequested(string addressHex, string optionalTipHex)
    signal submitRequested(string channelIdHex, var inputNoteIdHexes,
                           string metadataBase58, string changePublicKeyHex,
                           var fundingPublicKeyHexes, string maxTxFee,
                           string optionalTipHex)
    signal copyToClipboard(string text)

    // ---- Results back in ----
    function setTransferHash(hash) { transferView.setTransferHash(hash) }
    function setTransferError(message) { transferView.setTransferError(message) }
    function setNotes(value) { channelDepositView.setNotes(value) }
    function setNotesError(message) { channelDepositView.setNotesError(message) }
    function setSubmitResult(success, value) {
        channelDepositView.setSubmitResult(success, value)
    }

    spacing: Theme.spacing.large

    SectionNav {
        objectName: "walletNav"
        // Index-for-index with walletStack's children below.
        sections: [
            { label: qsTr("Accounts"), icon: "", needsNode: true },
            { label: qsTr("Transfer"), icon: "", needsNode: true },
            { label: qsTr("Channel Deposit"), icon: "", needsNode: true }
        ]
        nodeRunning: root.nodeRunning
        currentIndex: walletStack.currentIndex
        onSectionActivated: (index) => walletStack.currentIndex = index
    }

    LogosFrame {
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: StackLayout {
            id: walletStack

            AccountsView {
                id: accountsView
                accountsModel: root.accountsModel
                onRefreshAccountsRequested: root.refreshAccountsRequested()
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            TransferView {
                id: transferView
                accountRows: root.accountRows
                onTransferRequested: (fromKeyHex, toKeyHex, amount) =>
                    root.transferRequested(fromKeyHex, toKeyHex, amount)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }

            ChannelDepositView {
                id: channelDepositView
                accountRows: root.accountRows
                nodeRunning: root.nodeRunning
                onGetNotesRequested: (addressHex, optionalTipHex) =>
                    root.getNotesRequested(addressHex, optionalTipHex)
                onSubmitRequested: (channelIdHex, inputNoteIdHexes, metadataBase58,
                                    changePublicKeyHex, fundingPublicKeyHexes,
                                    maxTxFee, optionalTipHex) =>
                    root.submitRequested(channelIdHex, inputNoteIdHexes, metadataBase58,
                                         changePublicKeyHex, fundingPublicKeyHexes,
                                         maxTxFee, optionalTipHex)
                onCopyToClipboard: (text) => root.copyToClipboard(text)
            }
        }
    }
}
