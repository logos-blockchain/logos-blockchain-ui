import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units

// Leader rewards panel: claim action plus a read-only, horizontally-sliding
// list of the wallet's claimable ("pending") vouchers with a count. The
// protocol picks which voucher a claim consumes — the list is informational.
ColumnLayout {
    id: root

    // JSON from wallet_get_claimable_vouchers:
    //   { "tip": "<hex>", "reward_amount": "<u64>", "total_claimable": "<u64>",
    //     "vouchers": [ {commitment, nullifier}, ... ] }
    property string vouchersJson: ""

    signal claimLeaderRewardsRequested()
    signal copyToClipboard(string text)

    function setLeaderClaimResult(text) {
        leaderClaimResultText.text = text
    }

    QtObject {
        id: d

        function safeParse(s) {
            try { return s && s.length > 0 ? JSON.parse(s) : null } catch (e) { return null }
        }

        readonly property var parsed: safeParse(root.vouchersJson)
        readonly property var vouchers: (parsed && parsed.vouchers)
            ? parsed.vouchers
            : (Array.isArray(parsed) ? parsed : [])
        readonly property string tip: (parsed && parsed.tip) ? String(parsed.tip) : ""

        // Whether the wallet has answered at all. An empty payload is not an
        // empty wallet: the view is cleared whenever the node stops.
        readonly property bool reported: parsed !== null
        readonly property bool hasVouchers: vouchers.length > 0

        // Gated on holding a voucher, not on the field being there: the node
        // reports a network-wide rate whether or not this wallet can claim
        // against it. Note these arrive as decimal strings, so "0" is truthy
        // and a bare `&&` would let an empty wallet price itself.
        readonly property string perVoucher:
            (hasVouchers && parsed && parsed.reward_amount)
            ? Units.format(String(parsed.reward_amount)) : ""
        readonly property string totalClaimable:
            (hasVouchers && parsed && parsed.total_claimable)
            ? Units.format(String(parsed.total_claimable)) : ""
    }

    spacing: Theme.spacing.large

    // ---- Claimable vouchers card ----
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            id: vouchersCol
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Claimable vouchers")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                // Pending counter badge
                LogosBadge {
                    visible: d.reported
                    text: qsTr("%1 pending").arg(d.vouchers.length)
                    backgroundColor: Theme.palette.backgroundSecondary
                    borderColor: Theme.palette.border
                    labelItem.color: Theme.palette.textSecondary
                    labelItem.font.pixelSize: Theme.typography.secondaryText
                }
                Item { Layout.fillWidth: true }
                LogosText {
                    visible: d.tip.length > 0
                    text: qsTr("tip %1").arg(d.tip)
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 140
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                LogosInfoButton {
                    title: qsTr("Leader Rewards")
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Claim block-leader rewards. The list shows your pending claimable vouchers, refreshed each block; claiming submits a transaction and the protocol selects which voucher it consumes. The amounts are the node's estimate at the tip above, not a figure you are owed: the reward pool is split across every unclaimed voucher on the network, so it falls as other leaders claim theirs. The claim's own transaction fee is not deducted — it is not known until the transaction is built, so expect to receive slightly less than shown.")
                }
            }

            LogosText {
                visible: d.totalClaimable.length > 0
                text: qsTr("≈%1").arg(d.totalClaimable)
                font.pixelSize: Theme.typography.panelTitleText
                font.weight: Theme.typography.weightBold
                color: Theme.palette.text
            }

            LogosText {
                visible: d.perVoucher.length > 0
                text: qsTr("%n voucher(s)", "", d.vouchers.length)
                      + qsTr(" × %1 each · before fees").arg(d.perVoucher)
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            // Horizontally-sliding list of voucher cards.
            ListView {
                id: vouchersList
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                visible: d.vouchers.length > 0
                orientation: ListView.Horizontal
                clip: true
                spacing: Theme.spacing.small
                model: d.vouchers
                snapMode: ListView.SnapToItem
                ScrollBar.horizontal: LogosScrollBar {
                    orientation: Qt.Horizontal
                    policy: ScrollBar.AsNeeded
                }

                delegate: Rectangle {
                    width: 260
                    height: ListView.view.height
                    radius: Theme.spacing.radiusSmall
                    color: Theme.palette.backgroundSecondary
                    border.color: Theme.palette.border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacing.small
                        spacing: Theme.spacing.tiny

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Theme.spacing.tiny

                            LogosText {
                                text: qsTr("Voucher %1").arg(index + 1)
                                font.pixelSize: Theme.typography.secondaryText
                                font.bold: true
                                color: Theme.palette.textSecondary
                            }

                            Item { Layout.fillWidth: true }

                            LogosText {
                                visible: d.perVoucher.length > 0
                                text: qsTr("≈%1").arg(d.perVoucher)
                                font.pixelSize: Theme.typography.secondaryText
                                font.weight: Theme.typography.weightMedium
                            }
                        }
                        VoucherField {
                            label: qsTr("cm")
                            value: modelData && modelData.commitment ? String(modelData.commitment) : ""
                        }
                        VoucherField {
                            label: qsTr("nf")
                            value: modelData && modelData.nullifier ? String(modelData.nullifier) : ""
                        }
                    }
                }
            }

            LogosText {
                visible: d.vouchers.length === 0
                text: d.reported ? qsTr("No claimable vouchers.")
                                    : qsTr("Start the node to see claimable vouchers.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }

    // ---- Claim action ----
    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge

        contentItem: RowLayout {
            id: claimRow

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
                        value: leaderClaimResultText.text
                        visible: leaderClaimResultText.text
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    // A labelled, elided, copyable hash inside a voucher card.
    component VoucherField: RowLayout {
        id: vf
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Theme.spacing.tiny
        LogosText {
            text: vf.label
            Layout.preferredWidth: 20
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            text: vf.value || "—"
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
            font.family: Theme.typography.mono
        }
        LogosCopyButton {
            Layout.preferredHeight: 24
            Layout.preferredWidth: 24
            visible: vf.value.length > 0
            value: vf.value
        }
    }
}
