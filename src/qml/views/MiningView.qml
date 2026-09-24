pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units
import "infoContent.js" as InfoContent

// Proof-of-Work mining and claiming.
//
// The counts here are the only place an operator can see whether claiming is
// working, because auto-claim runs unattended and reports its failures to the
// node log, which the app does not surface. Three measured figures carry that:
// tickets Ready to claim with how soon they expire, claims Awaiting payout, and
// Mining Rewards once they settle. Tickets climbing while the other two stay at
// zero is the symptom — stated by the numbers rather than by a verdict.
ColumnLayout {
    id: root

    // --- Public API ---

    property bool nodeRunning: false
    // Claims sent from here that have not been seen on chain yet. Auto-claim
    // does not pass through the app, so this counts only manual claims — it is
    // added to pendingCount rather than shown alone, which is what makes the
    // figure mean the same thing in both modes.
    property int submittedCount: 0
    property string powRewardsLepta: ""
    property int claimableTickets: 0
    property int soonestExpirySlots: -1
    property int soonestExpiryCount: 0
    property bool claimableLoaded: false
    property string claimableError: ""
    property var accounts: []

    property bool claimBusy: false
    property bool claimSuccess: false
    property string claimMessage: ""

    signal claimRequested(string addressHex)

    // ---- Claim history ----
    // Remoted ClaimsModel scoped to mining. Null until the replica resolves.
    property var claimsModel: null
    // get_time_info payload; only slot_duration_ms and genesis_time_unix_ms are
    // read, to turn a claim's slot into a date.
    property string timeInfoJson: ""
    property int pendingCount: 0
    // Why the node cannot answer, or empty when it can.
    property string nodeOffReason: ""
    // A LogosNotice.Severity for the banner above.
    property int nodeOffSeverity: LogosNotice.Info

    signal historyPendingOnlyChanged(bool pendingOnly)
    signal openInExplorerRequested(string id)

    spacing: Theme.spacing.medium

    QtObject {
        id: d

        property string selectedAddress: ""

        function safeParse(text) {
            try { return text && text.length > 0 ? JSON.parse(text) : null }
            catch (e) { return null }
        }
        readonly property var timeInfo: safeParse(root.timeInfoJson)
        // Two numbers, not the payload: a delegate should not re-parse this
        // JSON once per visible row for a value identical on every row.
        readonly property real slotDurationMs:
            (timeInfo && timeInfo.slot_duration_ms) ? Number(timeInfo.slot_duration_ms) : 0
        readonly property real genesisTimeMs:
            (timeInfo && timeInfo.genesis_time_unix_ms) ? Number(timeInfo.genesis_time_unix_ms) : 0
        readonly property string expiryCaption: {
            if (!root.claimableLoaded || root.soonestExpirySlots < 0)
                return ""
            return qsTr("%1 expiring in %2 slots")
                       .arg(root.soonestExpiryCount)
                       .arg(root.soonestExpirySlots)
        }

        readonly property string awaitingPayoutCaption: {
            if (root.submittedCount > 0 && root.pendingCount > 0)
                return qsTr("%1 sent · %2 settling")
                           .arg(root.submittedCount).arg(root.pendingCount)
            if (root.pendingCount > 0)
                return qsTr("%n settling", "", root.pendingCount)
            if (root.submittedCount > 0)
                return qsTr("%n sent, not seen yet", "", root.submittedCount)
            return ""
        }
    }

    NodeOffNotice {
        reason: root.nodeOffReason
        reasonSeverity: root.nodeOffSeverity
    }

    // ---- Header ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        LogosText {
            text: qsTr("Tickets")
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
        }

        LogosText {
            text: qsTr("Mining searches for tickets; unclaimed tickets expire.")
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }

        Item { Layout.fillWidth: true }

        LogosInfoButton {
            Layout.alignment: Qt.AlignVCenter
            title: qsTr("Mining")
            dialogContentItem: InfoSections { info: InfoContent.miningOverview }
        }
    }

    // ---- Counters ----
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        spacing: Theme.spacing.medium

        LogosStatCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            objectName: "claimableTicketsCard"
            label: qsTr("Ready to claim")
            value: root.claimableLoaded ? String(root.claimableTickets) : "—"
            flashOnChange: root.visible
            caption: d.expiryCaption
            labelTrailing: [
                LogosInfoButton {
                    title: qsTr("Ready to claim")
                    dialogContentItem: InfoSections { info: InfoContent.claimableTickets }
                }
            ]
        }

        LogosStatCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            objectName: "awaitingPayoutCard"
            label: qsTr("Awaiting payout")
            value: String(root.submittedCount + root.pendingCount)
            caption: d.awaitingPayoutCaption
            flashOnChange: root.visible
            labelTrailing: [
                LogosInfoButton {
                    title: qsTr("Awaiting payout")
                    dialogContentItem: InfoSections { info: InfoContent.awaitingPayout }
                }
            ]
        }

        LogosStatCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            objectName: "miningRewardsCard"
            label: qsTr("Mining Rewards")
            value: root.powRewardsLepta.length > 0
                   ? Units.compact(root.powRewardsLepta) : Units.compact("0")
            flashOnChange: root.visible
            labelTrailing: [
                LogosInfoButton {
                    title: qsTr("Mining Rewards")
                    dialogContentItem: InfoSections { info: InfoContent.miningRewards }
                }
            ]
        }
    }

    // The poll's own failure, with room to be read.
    LogosNotice {
        Layout.fillWidth: true
        objectName: "claimableErrorNotice"
        shown: root.claimableError.length > 0
        severity: LogosNotice.Warning
        title: qsTr("Can't read claimable tickets")
        message: root.claimableError
    }

    // ---- Manual claim ----
    LogosText {
        Layout.topMargin: Theme.spacing.small
        text: qsTr("Claim now")
        font.pixelSize: Theme.typography.primaryText
    }

    LogosText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: qsTr("Pays the tickets mined so far. Leave the account unset to let the node pay "
                   + "whichever claim target is furthest below its threshold — the same choice "
                   + "auto-claim makes.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosComboBox {
            id: accountCombo
            objectName: "claimAccountCombo"
            Layout.fillWidth: true
            enabled: root.nodeRunning && !root.claimBusy
            textRole: "label"
            valueRole: "address"
            model: root.accounts
            currentIndex: -1
            displayText: currentIndex < 0
                         ? qsTr("Let the node choose")
                         : currentText
            onActivated: d.selectedAddress = accountCombo.currentValue
        }

        LogosButton {
            objectName: "clearClaimAccountButton"
            text: qsTr("Clear")
            visible: accountCombo.currentIndex >= 0
            enabled: !root.claimBusy
            onClicked: {
                accountCombo.currentIndex = -1
                d.selectedAddress = ""
            }
        }

        LogosButton {
            objectName: "claimNowButton"
            variant: LogosButton.Variant.Primary
            text: root.claimBusy ? qsTr("Claiming…") : qsTr("Claim")
            enabled: root.nodeRunning && !root.claimBusy && root.claimableTickets > 0
            onClicked: root.claimRequested(d.selectedAddress)
        }
    }

    LogosSelectableText {
        Layout.fillWidth: true
        objectName: "claimResultText"
        wrapMode: TextEdit.Wrap
        visible: root.claimMessage.length > 0
        text: root.claimMessage
        font.pixelSize: Theme.typography.secondaryText
        color: root.claimSuccess ? Theme.palette.success : Theme.palette.error
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
}
