import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units
import "infoContent.js" as InfoContent

// Leader rewards panel
ColumnLayout {
    id: root

    // JSON from wallet_get_claimable_vouchers:
    //   { "tip": "<hex>", "reward_amount": "<u64>", "total_claimable": "<u64>",
    //     "vouchers": [ {commitment, nullifier}, ... ] }
    property string vouchersJson: ""
    // Remoted ClaimsModel — roles: kind, value, payee, blockId, txHash, slot,
    // nullifier, confirmed. Null until the replica resolves.
    property var claimsModel: null
    // get_time_info payload; only slot_duration_ms and genesis_time_unix_ms are
    // read, to turn a claim's slot into a date.
    property string timeInfoJson: ""
    // Claims sent from here that have not been seen on chain yet. Auto-claim
    // does not pass through the app, so a zero is not "nothing is happening".
    property int submittedCount: 0
    // Claims in a block but not yet final. Published by the backend rather than
    // counted from the model, because with the filter on the model holds only
    // pending rows and could never report zero.
    property int pendingCount: 0

    signal claimLeaderRewardsRequested()
    signal copyToClipboard(string text)
    signal historyPendingOnlyChanged(bool pendingOnly)
    signal openInExplorerRequested(string id)

    property string claimResult: ""
    property bool claimSucceeded: false

    function setLeaderClaimResult(text, success) {
        root.claimResult = text
        root.claimSucceeded = success === true
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

        // ---- Claim history ------------------------------------------------
        readonly property var timeInfo: safeParse(root.timeInfoJson)

        // Parsed once here, handed to every delegate as two numbers — a
        // delegate should not re-parse this JSON per visible row.
        readonly property real slotDurationMs:
            (timeInfo && timeInfo.slot_duration_ms) ? Number(timeInfo.slot_duration_ms) : 0
        readonly property real genesisTimeMs:
            (timeInfo && timeInfo.genesis_time_unix_ms) ? Number(timeInfo.genesis_time_unix_ms) : 0
    }

    spacing: Theme.spacing.large

    // ---- Header ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        LogosText {
            text: qsTr("Vouchers")
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
        }

        LogosText {
            text: qsTr("Claimed manually — one claim redeems one voucher.")
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }

        Item { Layout.fillWidth: true }

        LogosButton {
            id: leaderClaimButton
            Layout.preferredWidth: 140
            variant: LogosButton.Variant.Primary
            text: qsTr("Claim")
            onClicked: root.claimLeaderRewardsRequested()
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        columnSpacing: Theme.spacing.medium
        rowSpacing: Theme.spacing.medium
        columns: Math.max(1, Math.floor((width + columnSpacing) / (180 + columnSpacing)))

        LogosStatCard {
            Layout.fillWidth: true
            objectName: "readyToClaimCard"
            label: qsTr("Ready to claim")
            value: d.reported ? String(d.vouchers.length) : "—"
            caption: d.totalClaimable.length > 0
                     ? qsTr("≈%1 before fees").arg(d.totalClaimable) : ""
            flashOnChange: root.visible
            interactive: d.hasVouchers
            onClicked: if (d.hasVouchers) voucherDialog.open()
            labelTrailing: [
                LogosInfoButton {
                    title: qsTr("Ready to claim")
                    dialogContentItem: InfoSections { info: InfoContent.readyToClaim }
                }
            ]
        }

        LogosStatCard {
            Layout.fillWidth: true
            objectName: "submittedClaimsCard"
            label: qsTr("Submitted")
            value: String(root.submittedCount)
            caption: root.submittedCount > 0 ? qsTr("waiting to land") : ""
            flashOnChange: root.visible
            labelTrailing: [
                LogosInfoButton {
                    title: qsTr("Submitted")
                    dialogContentItem: InfoSections { info: InfoContent.submitted }
                }
            ]
        }
    }

    // ---- Claim result ----
    LogosNotice {
        Layout.fillWidth: true
        objectName: "claimResultNotice"
        shown: root.claimResult.length > 0
        severity: root.claimSucceeded ? LogosNotice.Success : LogosNotice.Error
        title: root.claimSucceeded ? qsTr("Claim submitted") : qsTr("Claim failed")
        message: root.claimResult
        closable: true
        onDismissed: root.setLeaderClaimResult("", false)
        actions: [
            LogosCopyButton {
                value: root.claimResult
            }
        ]
    }

    // ---- Claim history ----
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        spacing: Theme.spacing.medium

        LogosText {
            text: qsTr("History")
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
        }
        Item { Layout.fillWidth: true }

        LogosCheckbox {
            id: pendingOnlyCheck
            Layout.alignment: Qt.AlignVCenter
            visible: root.pendingCount > 0 || checked
            text: qsTr("Show only pending")
            font.pixelSize: Theme.typography.secondaryText
            onToggled: root.historyPendingOnlyChanged(checked)
        }

        LogosText {
            visible: claimsList.count > 0
            text: qsTr("%n claim(s)", "", claimsList.count)
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }
    }

    LogosText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: claimsList.count === 0
        text: root.claimsModel === null
              ? qsTr("Loading…")
              : pendingOnlyCheck.checked
                ? qsTr("Nothing pending — every claim has reached finality.")
                : qsTr("No claims recorded yet. Rewards appear here once a claim settles.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }

    ListView {
        id: claimsList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 120
        visible: count > 0
        clip: true
        spacing: Theme.spacing.small
        model: root.claimsModel
        ScrollBar.vertical: LogosScrollBar { policy: ScrollBar.AsNeeded }

        delegate: ClaimDelegate {
            slotDurationMs: d.slotDurationMs
            genesisTimeMs: d.genesisTimeMs
            onOpenInExplorerRequested: (id) => root.openInExplorerRequested(id)
        }
    }

    // ---- Voucher detail, opened from the Ready to claim tile ----
    // Parented to the overlay and centred there, the way LogosInfoButton does
    // it: a Popup anchored inside this ColumnLayout would be clipped by it and
    // would fight the layout for a size.
    LogosDialog {
        id: voucherDialog

        readonly property Item hostOverlay: Overlay.overlay
        parent: hostOverlay
        anchors.centerIn: parent

        title: d.hasVouchers
               ? qsTr("Ready to claim · %n voucher(s)", "", d.vouchers.length)
               : qsTr("Ready to claim")
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: hostOverlay ? Math.min(520, hostOverlay.width - 2 * Theme.spacing.xxlarge) : 520
        readonly property real maxHeight:
            hostOverlay ? hostOverlay.height - 2 * Theme.spacing.xxlarge : 600
        height: Math.min(implicitHeight, maxHeight)

        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: d.tip.length > 0
                spacing: Theme.spacing.tiny

                LogosText {
                    text: qsTr("as of tip")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textTertiary
                }
                LogosText {
                    Layout.fillWidth: true
                    text: d.tip
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.typography.secondaryText
                    font.family: Theme.typography.mono
                    color: Theme.palette.textTertiary
                }
                LogosCopyButton {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: 24
                    value: d.tip
                }
            }

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !d.hasVouchers
                text: d.reported ? qsTr("Nothing left to claim.")
                                 : qsTr("Start the node to see claimable vouchers.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                visible: d.hasVouchers
                clip: true
                spacing: Theme.spacing.small
                model: d.vouchers
                ScrollBar.vertical: LogosScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: ListView.view.width
                    height: voucherCol.implicitHeight + Theme.spacing.small * 2
                    radius: Theme.spacing.radiusSmall
                    color: Theme.palette.backgroundSecondary
                    border.color: Theme.palette.border
                    border.width: 1

                    ColumnLayout {
                        id: voucherCol
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
                        HashRow {
                            Layout.fillHeight: false
                            label: qsTr("cm")
                            labelWidth: 28
                            value: modelData && modelData.commitment
                                   ? String(modelData.commitment) : ""
                        }
                        HashRow {
                            Layout.fillHeight: false
                            label: qsTr("nf")
                            labelWidth: 28
                            value: modelData && modelData.nullifier
                                   ? String(modelData.nullifier) : ""
                        }
                    }
                }
            }
        }

        rightActions: [
            LogosButton {
                objectName: "dialogClaimButton"
                variant: LogosButton.Variant.Primary
                enabled: d.hasVouchers
                text: qsTr("Claim")
                onClicked: root.claimLeaderRewardsRequested()
            }
        ]
    }
}
