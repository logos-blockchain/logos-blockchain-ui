pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// The Blend Core dialog once a declaration exists: the joining stepper, the
// status card (active, inactive, leaving), and the leave confirmation.
ColumnLayout {
    id: root

    property BlendCoreState blend

    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: root.blend.declared
    spacing: Theme.spacing.small

    // ================= joining =================
    ColumnLayout {
        id: progress
        objectName: "blendProgress"
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.blend.joining && !root.blend.confirmingLeave
        spacing: Theme.spacing.small

        Timer {
            interval: 30000
            repeat: true
            running: parent.visible
            onTriggered: root.blend.now = Date.now()
        }

        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.blend.step === 0
                  ? qsTr("Declaration submitted")
                  : root.blend.activationEta.length > 0
                    ? qsTr("Activating — Core at epoch %1 (%2)").arg(root.blend.activeFrom)
                      .arg(root.blend.activationEta)
                    : qsTr("Activating — Core at epoch %1").arg(root.blend.activeFrom)
            color: Theme.palette.text
            font.pixelSize: Theme.typography.primaryText
            font.weight: Theme.typography.weightMedium
        }
        LogosText {
            Layout.fillWidth: true
            text: root.blend.step === 0
                  ? qsTr("Waiting for it to land in a block. You can close this window.")
                  : qsTr("Your declaration is on-chain and your stake is locked. You "
                         + "can close this window; activation continues in the "
                         + "background.")
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        // Labelled, so it reads as progress rather than a scrollbar.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.small
            spacing: Theme.spacing.small
            Repeater {
                model: [qsTr("Submitted"), qsTr("In a block"),
                        root.blend.activeFrom >= 0 ? qsTr("Core at epoch %1").arg(root.blend.activeFrom)
                                          : qsTr("Core")]
                delegate: ColumnLayout {
                    id: stepItem
                    required property int index
                    required property string modelData
                    readonly property bool reached: stepItem.index <= root.blend.step
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: Theme.spacing.tiny
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: stepItem.reached ? Theme.palette.primary
                                                : Theme.palette.border
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: stepItem.modelData
                        elide: Text.ElideRight
                        color: stepItem.reached ? Theme.palette.text
                                                : Theme.palette.textTertiary
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // ================= declared: status card =================
    ColumnLayout {
        id: statusCard
        objectName: "blendStatusCard"
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.blend.declared && !root.blend.joining && !root.blend.confirmingLeave
        spacing: Theme.spacing.small

        LogosFrame {
            Layout.fillWidth: true
            backgroundColor: Theme.palette.surfaceRaised
            borderColor: "transparent"
            radius: Theme.spacing.radiusMedium

            RowLayout {
                id: cardRow
                anchors.fill: parent
                spacing: Theme.spacing.medium

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: 9
                    color: root.blend.withdrawn ? Theme.palette.textTertiary
                         : root.blend.active ? root.blend.gold
                         : root.blend.inactive ? Theme.palette.error
                         : Theme.palette.info
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    LogosText {
                        text: root.blend.withdrawn ? qsTr("Leaving — withdrawal submitted")
                            : root.blend.active ? qsTr("Active — mixing for the network")
                            : root.blend.inactive ? qsTr("Not active — missed its activity")
                            : qsTr("Declared — activating at epoch %1")
                              .arg(root.blend.declaration ? root.blend.declaration.active_from_epoch : "?")
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                    }
                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.palette.textTertiary
                        font.pixelSize: 11
                        text: {
                            if (root.blend.withdrawn)
                                return root.blend.withdrawAt === null
                                    ? qsTr("waiting for a block")
                                    : qsTr("serves through epoch %1 · stake unlocks at "
                                           + "epoch %2 (now epoch %3)")
                                      .arg(root.blend.withdrawAt - 1).arg(root.blend.withdrawAt + 1)
                                      .arg(root.blend.blendStatus.current_epoch)
                            if (root.blend.active) {
                                const peers = root.blend.blendStatus.session_peers
                                const n = peers ? peers.total : 0
                                const proof = !root.blend.activity ? ""
                                    : root.blend.activity.this_epoch === "accepted"
                                      ? qsTr("activity proof accepted")
                                    : root.blend.activity.this_epoch === "failed"
                                      ? qsTr("no activity recorded")
                                    : qsTr("collecting activity")
                                return n > 0 ? qsTr("%1 core peers this epoch · %2").arg(n).arg(proof)
                                             : proof
                            }
                            if (root.blend.inactive)
                                return qsTr("running as Edge · not in this epoch's core set")
                            return qsTr("enters the core set at epoch %1 (now epoch %2)")
                                   .arg(root.blend.declaration ? root.blend.declaration.active_from_epoch : "?")
                                   .arg(root.blend.blendStatus.current_epoch)
                        }
                    }
                }
            }
        }

        LogosText {
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            text: {
                if (root.blend.withdrawn)
                    return qsTr("Rewards for the epochs it still serves are paid as "
                                + "usual. You can declare again once the stake is "
                                + "unlocked.")
                if (!root.blend.activity || root.blend.activity.this_epoch !== "failed")
                    return ""
                switch (root.blend.activity.reason) {
                case "no_proof":
                    return qsTr("No proof this epoch. Either no other Blend node "
                                + "reached yours (check the port forwarding) or the "
                                + "draw missed; an occasional miss is normal.")
                case "fee_failed":
                    return qsTr("The SdpFunding key couldn't pay the activity fee. "
                                + "Top it up.")
                case "post_failed":
                    return qsTr("The activity proof was rejected by the chain.")
                case "network_below_minimum":
                    return qsTr("The Blend network is below its minimum size, so no "
                                + "activity counts this epoch.")
                default:
                    return ""
                }
            }
        }

        LogosFrame {
            Layout.fillWidth: true
            backgroundColor: Theme.palette.surfaceRaised
            borderColor: "transparent"
            radius: Theme.spacing.radiusMedium

            ColumnLayout {
                id: facts
                anchors.fill: parent
                spacing: Theme.spacing.small

                BlendJoinPages.Fact {
                    label: qsTr("Messages handled")
                    value: root.blend.activity && root.blend.active ? String(root.blend.activity.tokens_collected) : ""
                }
                BlendJoinPages.Fact {
                    label: qsTr("Last active epoch")
                    value: root.blend.activity && root.blend.activity.last_active_epoch !== null
                           && root.blend.activity.last_active_epoch !== undefined
                           ? String(root.blend.activity.last_active_epoch) : ""
                }
                BlendJoinPages.Fact {
                    label: qsTr("Fee funds left")
                    value: {
                        if (root.blend.sdpFundingBalance.length === 0)
                            return ""
                        const fee = root.blend.activity && root.blend.activity.last_fee ? Number(root.blend.activity.last_fee) : 0
                        return fee > 0
                               ? qsTr("%1 (about %2 epochs)")
                                 .arg(Units.format(root.blend.sdpFundingBalance))
                                 .arg(Math.floor(Number(root.blend.sdpFundingBalance) / fee))
                               : Units.format(root.blend.sdpFundingBalance)
                    }
                }
                BlendJoinPages.Fact {
                    label: qsTr("Published address")
                    value: root.blend.declaration && root.blend.declaration.locators ? root.blend.declaration.locators[0] : ""
                    mono: true
                }
                BlendJoinPages.Fact {
                    label: qsTr("Locked stake note")
                    value: root.blend.declaration ? root.blend.declaration.locked_note_id : ""
                    mono: true
                    copyable: true
                }
                BlendJoinPages.Fact {
                    label: qsTr("Declaration")
                    value: root.blend.declaration ? root.blend.declaration.id : ""
                    mono: true
                    copyable: true
                }
            }
        }
    }

    // ================= leave =================
    ColumnLayout {
        id: leavePage
        objectName: "blendLeave"
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.blend.confirmingLeave && !root.blend.withdrawn
        spacing: Theme.spacing.small

        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Withdrawing takes this node out of the Blend core set and "
                       + "unlocks its stake.")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        LogosFrame {
            Layout.fillWidth: true
            backgroundColor: Theme.palette.surfaceRaised
            borderColor: "transparent"
            radius: Theme.spacing.radiusMedium

            // Epochs assume the withdrawal lands this epoch.
            ColumnLayout {
                id: leaveFacts
                anchors.fill: parent
                spacing: Theme.spacing.small

                BlendJoinPages.Fact {
                    label: qsTr("Keeps mixing through")
                    value: qsTr("epoch %1").arg((root.blend.blendStatus.current_epoch || 0) + 1)
                }
                BlendJoinPages.Fact {
                    label: qsTr("Stake unlocks at")
                    value: qsTr("epoch %1")
                           .arg((root.blend.blendStatus.current_epoch || 0) + root.blend.unlockDelay)
                }
                BlendJoinPages.Fact {
                    label: qsTr("Locked stake note")
                    value: root.blend.declaration ? root.blend.declaration.locked_note_id : ""
                    mono: true
                }
                BlendJoinPages.Fact {
                    label: qsTr("Fee")
                    value: qsTr("a small fee from your SDP funding key")
                }
            }
        }

        BlendJoinPages.NoteBlock {
            title: qsTr("Rewards stay yours")
            message: qsTr("Rewards already earned stay on your BlendZk key, and the "
                          + "epochs it still serves are paid as usual. You can declare "
                          + "again once the stake is unlocked.")
        }
    }
}
