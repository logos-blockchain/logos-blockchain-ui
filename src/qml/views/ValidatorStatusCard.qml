import QtQuick
import QtQml
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

// The design's validator panel, reduced to what the node actually reports.
//
// Kept as one card rather than the design's Validator Status + Rewards pair:
// with the unavailable fields removed there are three values between them, and
// the split's logic came from precisely those missing fields. Split it again
// when the data lands, not before.
//
// Left out, all blocked on node-side work (logos-blockchain-module#61):
//   * "Aged – Participating" — a UTXO is eligible two epochs after minting
//     (ledger/src/cryptarchia/mod.rs), but nothing reports whether this
//     wallet's notes have aged, nor whether leadership is running.
//   * "Total Claimed" — no cumulative total is kept, and it cannot be
//     reconstructed here: the tx store is mempool-only and pruned soon after
//     inclusion.
//   * "N LGO available to claim" — a Voucher is {nullifier, commitment} with
//     no value; the reward lives on the ledger (leader_reward_amount) and is
//     not exposed.
Control {
    id: root

    // --- Public API ---
    required property var accountsModel
    // wallet_get_claimable_vouchers payload: { tip, vouchers: [...] }.
    property string vouchersJson: ""
    property bool canClaim: false

    signal claimRequested()

    readonly property alias _d: d

    QtObject {
        id: d

        readonly property int accountCount: accounts.count

        function rowAt(i) {
            return (i >= 0 && i < accountCount) ? accounts.objectAt(i) : null
        }

        function balanceAt(i) {
            const row = rowAt(i)
            return row ? String(row.balance || "").trim() : ""
        }

        // Balances are u64 rendered as decimal strings, and a u64 runs past
        // 2^53 where Number() silently loses precision. BigInt literals don't
        // parse in QML, so add the decimal strings directly — schoolbook
        // addition, right to left, exact at any width.
        function addDecimal(a, b) {
            let out = ""
            let carry = 0
            let i = a.length - 1
            let j = b.length - 1
            while (i >= 0 || j >= 0 || carry > 0) {
                const digit = (i >= 0 ? a.charCodeAt(i) - 48 : 0)
                            + (j >= 0 ? b.charCodeAt(j) - 48 : 0)
                            + carry
                out = String(digit % 10) + out
                carry = digit >= 10 ? 1 : 0
                i -= 1
                j -= 1
            }
            return out.length > 0 ? out : "0"
        }

        function stripLeadingZeros(v) {
            const trimmed = v.replace(/^0+/, "")
            return trimmed.length > 0 ? trimmed : "0"
        }

        readonly property var totals: {
            let sum = "0"
            let known = 0
            for (let i = 0; i < accountCount; i++) {
                const b = balanceAt(i)
                if (!/^[0-9]+$/.test(b))
                    continue
                sum = addDecimal(sum, b)
                known += 1
            }
            return { text: known > 0 ? stripLeadingZeros(sum) : "", known: known }
        }

        readonly property string totalBalance: totals.text
        // A balance stays empty when its lookup failed, so a total built from a
        // subset would read as the whole holding. Say so rather than imply it.
        readonly property bool partial: totals.known > 0 && totals.known < accountCount

        readonly property var parsed: {
            if (!root.vouchersJson || root.vouchersJson.length === 0)
                return null
            try {
                return JSON.parse(root.vouchersJson)
            } catch (e) {
                return null
            }
        }

        readonly property int voucherCount:
            (parsed && parsed.vouchers) ? parsed.vouchers.length : 0
    }

    Instantiator {
        id: accounts
        model: root.accountsModel
        delegate: QtObject {
            required property string address
            required property string balance
        }
    }

    background: Rectangle {
        color: Theme.palette.background
    }

    contentItem: LogosFrame {
        clip: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusXlarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosIcon {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Qt.resolvedUrl("../icons/open-arm-line.svg")
                    color: Theme.palette.primary
                }

                LogosText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    text: qsTr("Validator Status")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // ---- Total balance ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.tiny

                LogosText {
                    text: qsTr("Total Balance")
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                }

                LogosText {
                    Layout.fillWidth: true
                    text: d.totalBalance.length > 0 ? d.totalBalance : qsTr("—")
                    color: Theme.palette.text
                    // Design: DM Sans 400 38px/49 — matches the stats tiles.
                    font.pixelSize: 38
                    font.weight: Theme.typography.weightRegular
                    elide: Text.ElideRight
                }

                LogosText {
                    Layout.fillWidth: true
                    visible: d.partial
                    text: qsTr("%1 of %2 accounts reported").arg(d.totals.known).arg(d.accountCount)
                    color: Theme.palette.warning
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideRight
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // ---- Vouchers ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: false
                    spacing: Theme.spacing.tiny

                    LogosText {
                        text: qsTr("Vouchers Ready to Claim")
                        color: Theme.palette.textTertiary
                        font.pixelSize: Theme.typography.secondaryText
                    }

                    LogosText {
                        text: String(d.voucherCount)
                        color: Theme.palette.text
                        font.pixelSize: 38
                        font.weight: Theme.typography.weightRegular
                    }
                }

                Item { Layout.fillWidth: true }

                LogosButton {
                    // Bottom-aligned so it sits on the count's baseline rather
                    // than floating midway between the label and the number.
                    Layout.alignment: Qt.AlignBottom
                    text: qsTr("Claim")
                    enabled: root.canClaim && d.voucherCount > 0
                    onClicked: root.claimRequested()
                }
            }
        }
    }
}
