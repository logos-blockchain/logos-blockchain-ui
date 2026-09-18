import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Accounts panel: the known wallet addresses, what each one is for, and its
// balance. One Refresh covers the lot — the backend reads addresses and
// balances in the same call — so there is nothing per-row to press.
ColumnLayout {
    id: root

    required property var accountsModel

    signal refreshAccountsRequested()
    signal copyToClipboard(string text)

    spacing: Theme.spacing.large

    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        LogosButton {
            id: refreshButton
            Layout.alignment: Qt.AlignVCenter
            text: qsTr("Refresh")
            padding: Theme.spacing.small
            onClicked: root.refreshAccountsRequested()

            LogosToolTip {
                text: qsTr("Refreshes every wallet account and its balance")
                placement: LogosToolTip.Placement.Bottom
                visible: refreshButton.hovered
            }
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
            onCopyRequested: (text) => root.copyToClipboard(text)
        }
    }
}
