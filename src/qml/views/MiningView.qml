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

    // ---- PoW runtime state ----
    property bool miningActive: false
    // The node's PoW service answers nothing until the chain is online, so
    // neither mining nor auto-claim can be read or changed before then.
    property bool chainOnline: false
    property bool powStatusKnown: false
    property bool powRewardsEnabled: false
    property bool autoClaimArmed: false
    // Off because every target is done, rather than off because someone said so.
    property bool autoClaimSelfDisarmed: false
    property int autoClaimTick: 0
    property string autoClaimTickUnit: ""
    // Rows of { address, thresholdLepta, balanceLepta, balanceKnown, reached,
    // noCap }.
    property var claimTargets: []

    signal claimRequested(string addressHex)
    signal autoClaimToggled(bool enabled)

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

        // The friendly name the claim combo uses for the same address.
        function accountLabel(address) {
            for (var i = 0; i < root.accounts.length; ++i) {
                if (root.accounts[i].address === address)
                    return root.accounts[i].label || ""
            }
            return ""
        }

        // Tickets are piling up and nothing is going to claim them. The
        // combination the app could not see before pow_status, and the one that
        // cost 170k tickets in logos-blockchain-module#86.
        // One line under the auto-claim switch; the first that applies wins.
        readonly property string autoClaimHint: {
            if (!root.nodeRunning)
                return ""
            if (!root.powStatusKnown && !root.chainOnline)
                return qsTr("Available once the node is online.")
            if (!root.powStatusKnown)
                return qsTr("This node's module does not report auto-claim's state, so the "
                            + "switch shows what was last asked for.")
            if (root.claimTargets.length === 0)
                return qsTr("No auto-claim targets configured — add them under "
                            + "pow.auto_claim.targets in the config, then restart the node.")
            if (root.autoClaimSelfDisarmed)
                return qsTr("Every target has reached the balance it stops at, so the node "
                            + "turns auto-claim off again as soon as it is switched on. Raise "
                            + "a threshold in the config's pow section to resume.")
            if (root.autoClaimArmed && !root.miningActive)
                return qsTr("On, but there is nothing to claim until mining is running.")
            return ""
        }

        readonly property bool miningIntoNothing:
            root.powStatusKnown && root.miningActive && !root.autoClaimArmed
            && root.claimableTickets > 0

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
            label: qsTr("Mining Rewards (%1)").arg(Units.SYMBOL)
            value: root.powRewardsLepta.length > 0
                   ? Units.compactPlain(root.powRewardsLepta) : Units.compactPlain("0")
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

    // Mining with no claimer. The one state where the numbers above look healthy
    // and are worthless: tickets climb, every one of them expires.
    LogosNotice {
        Layout.fillWidth: true
        objectName: "miningIntoNothingNotice"
        shown: d.miningIntoNothing
        severity: LogosNotice.Warning
        title: qsTr("Nothing is claiming these tickets")
        message: root.autoClaimSelfDisarmed
                 ? qsTr("Auto-claim is off and every claim target has already reached the "
                        + "balance it stops at, so switching it on would stop it again at "
                        + "once. Tickets expire unclaimed until a threshold is raised or "
                        + "you claim by hand below.")
                 : qsTr("Mining is on and auto-claim is off. Tickets expire unclaimed "
                        + "until auto-claim is switched on below or you claim by hand.")
    }

    LogosNotice {
        Layout.fillWidth: true
        objectName: "powRewardsDisabledNotice"
        shown: root.powStatusKnown && !root.powRewardsEnabled
        severity: LogosNotice.Info
        title: qsTr("This chain pays no mining rewards")
        message: qsTr("The node reports PoW rewards as disabled for this deployment, so "
                      + "mining here produces nothing to claim.")
    }

    // ---- Auto-claim ----
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Auto-claim")
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
        }

        LogosInfoButton {
            Layout.alignment: Qt.AlignVCenter
            title: qsTr("Auto-claim")
            dialogContentItem: InfoSections { info: InfoContent.autoClaim }
        }

        Item { Layout.fillWidth: true }

        LogosText {
            visible: root.autoClaimTick > 0
            text: root.autoClaimTickUnit === "slots"
                  ? qsTr("every %n slot(s)", "", root.autoClaimTick)
                  : qsTr("every %n second(s)", "", root.autoClaimTick)
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }

        // With no target the node refuses to arm and the switch would snap back,
        // so it can only be turned off then. A module without pow_status reports
        // no targets at all, which is not the same as having none.
        LogosSwitch {
            objectName: "autoClaimSwitch"
            checked: root.autoClaimArmed
            enabled: root.nodeRunning
                     && (root.chainOnline || root.powStatusKnown)
                     && (root.autoClaimArmed || !root.powStatusKnown
                         || root.claimTargets.length > 0)
            onToggled: root.autoClaimToggled(checked)
        }
    }

    LogosText {
        Layout.fillWidth: true
        objectName: "autoClaimHint"
        visible: text.length > 0
        wrapMode: Text.WordWrap
        text: d.autoClaimHint
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
    }

    Repeater {
        model: root.claimTargets

        delegate: RowLayout {
            id: targetRow

            required property var modelData

            readonly property string accountLabel: d.accountLabel(targetRow.modelData.address)

            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                visible: targetRow.accountLabel.length > 0
                text: targetRow.accountLabel
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            LogosText {
                objectName: "claimTargetAddress"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: targetRow.modelData.address
                elide: Text.ElideMiddle
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            LogosBadge {
                objectName: "claimTargetReachedBadge"
                visible: targetRow.modelData.reached === true
                text: qsTr("Threshold reached")
                color: Theme.palette.textTertiary
            }

            LogosText {
                objectName: "claimTargetBalance"
                text: {
                    const balance = targetRow.modelData.balanceKnown
                                    ? Units.compact(targetRow.modelData.balanceLepta)
                                    : qsTr("—")
                    return targetRow.modelData.noCap
                           ? qsTr("%1 · no cap").arg(balance)
                           : qsTr("%1 / %2").arg(balance)
                                            .arg(Units.compact(targetRow.modelData.thresholdLepta))
                }
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.text
            }
        }
    }

    // ---- Manual claim ----
    LogosText {
        Layout.topMargin: Theme.spacing.small
        text: qsTr("Manual claim")
        font.pixelSize: Theme.typography.subtitleText
        font.weight: Theme.typography.weightMedium
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
