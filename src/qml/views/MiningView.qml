pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "infoContent.js" as InfoContent

// Proof-of-Work mining and claiming.
//
// The counts here are the only place an operator can see that claiming is not
// working. Auto-claim runs unattended and reports failures to the node log,
// which the app does not surface — so a claimable count that climbs while
// nothing is ever claimed is the symptom, and this view is where it shows.
ColumnLayout {
    id: root

    // --- Public API ---

    property bool nodeRunning: false
    property bool autoClaimRunning: false
    // Claims sent from here that have not been seen on chain yet. Auto-claim
    // does not pass through the app, so a zero is not "nothing is happening".
    property int submittedCount: 0
    property int claimableTickets: 0
    property int soonestExpirySlots: -1
    property int soonestExpiryCount: 0
    property bool claimableLoaded: false
    property string claimableError: ""
    property var accounts: []

    property bool claimBusy: false
    property bool claimSuccess: false
    property string claimMessage: ""

    signal autoClaimToggled(bool enabled)
    signal claimRequested(string addressHex)

    // From the backend, which watches the claimable count fall.
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

    property bool claimsStalled: false
    // The window that flag is measured over. Read rather than restated: a number
    // in this message that disagreed with the rule would be worse than no number.
    property int claimStallSeconds: 0

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

        // How long a ticket lives is the node's `slot_window`, which nothing
        // reports to us — so the deadline is stated only where the node gives us
        // a real one, in slots, from slots_until_expiry. Everything else here is
        // either counted or published by the backend; no interval is invented.
        readonly property string stallMessage: {
            const minutes = Math.max(1, Math.round(root.claimStallSeconds / 60))
            let text = qsTr("%1 tickets are waiting and the count has not gone down in "
                            + "%2 minutes. They are accumulating faster than they are "
                            + "being claimed, and unclaimed tickets expire and cannot "
                            + "be recovered.")
                           .arg(root.claimableTickets)
                           .arg(minutes)
            if (root.soonestExpirySlots >= 0)
                text += "\n\n" + qsTr("%1 of them expire in %2 slots.")
                                     .arg(root.soonestExpiryCount)
                                     .arg(root.soonestExpirySlots)
            return text + "\n\n" + qsTr("Check that auto-claim is on and that your claim "
                                        + "threshold is above the target's current balance. "
                                        + "If it is, mining is simply producing tickets faster "
                                        + "than they can be redeemed — stop mining to let the "
                                        + "backlog clear.")
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
            valueColor: root.claimsStalled ? Theme.palette.warning : Theme.palette.text
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

    // The whole point of the view, when it fires: tickets are being mined into
    // nothing. Above the poll error because this is the one the user has to act
    // on — a failed poll costs a reading, this costs the rewards.
    LogosNotice {
        Layout.fillWidth: true
        objectName: "claimsStalledNotice"
        shown: root.claimsStalled
        severity: LogosNotice.Warning
        title: qsTr("Tickets are outrunning claims")
        message: d.stallMessage
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

    // ---- Auto-claim ----
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        implicitHeight: autoClaimColumn.implicitHeight + Theme.spacing.medium * 2
        color: Theme.palette.backgroundSecondary
        border.color: Theme.palette.border
        border.width: 1
        radius: Theme.spacing.radiusLarge

        ColumnLayout {
            id: autoClaimColumn
            anchors.fill: parent
            anchors.margins: Theme.spacing.medium
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small

                        LogosText {
                            text: qsTr("Auto-claim")
                            font.pixelSize: Theme.typography.primaryText
                        }
                        LogosBadge {
                            objectName: "autoClaimRecommendedBadge"
                            text: qsTr("Recommended")
                        }
                        Item { Layout.fillWidth: true }
                    }

                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.autoClaimRunning
                              ? qsTr("The node claims mined rewards on its own. It does not "
                                     + "report this back — if nothing is being claimed, trust "
                                     + "the ticket count over this switch.")
                              : qsTr("Tickets accumulate until you claim them below, and expire "
                                     + "if you do not.")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                }

                LogosSwitch {
                    objectName: "autoClaimSwitch"
                    checked: root.autoClaimRunning
                    enabled: root.nodeRunning && !root.claimBusy
                    onToggled: root.autoClaimToggled(checked)
                }
            }

            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Unattended claiming only works if the config file lists claim "
                           + "targets. Add one during onboarding or by editing the config "
                           + "directly — without one the node has nowhere to pay, and tickets "
                           + "expire however this switch is set.")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textTertiary
            }
        }
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
