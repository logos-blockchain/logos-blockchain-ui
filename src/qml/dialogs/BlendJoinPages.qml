import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../Units.js" as Units

// The Blend Core dialog before joining: the requirement checklist, then what
// joining publishes and locks. Its building blocks are inline components, also
// used by BlendStatusPages.
ColumnLayout {
    id: root

    property BlendCoreState blend

    // Closes every requirement's "i" again; the dialog does it on open.
    function collapse(): void {
        for (const item of checklist.children)
            if (item instanceof BlendCoreRequirement)
                item.expanded = false
    }

    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: !root.blend.declared
    spacing: Theme.spacing.small

    // A note in the same block style: an amber "!" for warnings, a grey "i"
    // for information.
    component NoteBlock: LogosFrame {
        id: note
        property bool warning: false
        property string title: ""
        property string message: ""

        Layout.fillWidth: true
        Layout.fillHeight: false
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusMedium

        RowLayout {
            anchors.fill: parent
            spacing: Theme.spacing.medium

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 18
                implicitHeight: 18
                radius: 9
                color: "transparent"
                border.width: 2
                border.color: note.warning ? Theme.palette.warning : Theme.palette.textTertiary
                LogosText {
                    anchors.centerIn: parent
                    text: note.warning ? "!" : "i"
                    color: note.warning ? Theme.palette.warning : Theme.palette.textTertiary
                    font.pixelSize: 11
                    font.weight: Theme.typography.weightBold
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                LogosText {
                    text: note.title
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }
                LogosText {
                    Layout.fillWidth: true
                    text: note.message
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textTertiary
                    font.pixelSize: 11
                }
            }
        }
    }

    component Fact: RowLayout {
        id: fact
        property string label: ""
        property string value: ""
        property bool mono: false
        property bool copyable: false

        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: fact.value.length > 0
        spacing: Theme.spacing.small

        LogosText {
            Layout.preferredWidth: 140
            text: fact.label
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            text: fact.value
            elide: Text.ElideMiddle
            color: Theme.palette.text
            font.family: fact.mono ? Theme.typography.mono : Theme.typography.publicSans
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosCopyButton {
            visible: fact.copyable
            value: fact.value
        }
    }

    // ================= requirements =================
    ColumnLayout {
        id: checklist
        objectName: "blendChecklist"
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !root.blend.declared && root.blend.page === "gates"
        spacing: Theme.spacing.small

        NoteBlock {
            visible: !root.blend.nodeRunning
            title: qsTr("The node isn't running")
            message: qsTr("Start it to check these requirements. If this node has "
                          + "already joined, its Blend status shows here once it runs.")
        }

        BlendCoreRequirement {
            objectName: "gateOnline"
            ok: root.blend.nodeRunning ? root.blend.onlineOk : false
            label: qsTr("Node synced")
            value: !root.blend.nodeRunning ? qsTr("Stopped")
                 : root.blend.nodeOnline ? qsTr("Online") : qsTr("Bootstrapping")
            fix: qsTr("Start the node to check the rest.")
        }

        BlendCoreRequirement {
            objectName: "gateFee"
            ok: root.blend.checked(root.blend.feeOk)
            label: qsTr("SDP funding key funded")
            value: root.blend.feeOk === null ? "" : Units.format(root.blend.sdpFundingBalance)
            fix: qsTr("Send some %1 to your SDP funding key to pay the joining fee.")
                 .arg(Units.SYMBOL)
            detail: qsTr("Joining pays a small fee from this key, and so does the "
                         + "activity proof a core node posts every epoch. Keep it "
                         + "funded: if it runs dry, the node stops proving its work "
                         + "and drops out after %1 epochs. Your SDP funding key:")
                    .arg(root.blend.requirements.inactivity_period || 2)
            copyValue: root.blend.sdpKey
        }

        BlendCoreRequirement {
            objectName: "gateStake"
            ok: root.blend.checked(root.blend.stakeOk)
            label: qsTr("Lockable stake note")
            value: root.blend.stakeOk === null ? ""
                 : root.blend.stakeOk ? qsTr("1 note ≥ %1").arg(Units.format(root.blend.minStake))
                 : qsTr("none")
            fix: qsTr("Send at least %1 to your BlendZk key in a single transfer.")
                 .arg(Units.format(root.blend.minStake))
            detail: qsTr("The stake is one coin, locked while you're a core provider. "
                         + "Send it with Wallet → Transfer, from any of your keys, "
                         + "including BlendZk itself. Mining rewards arrive in coins of "
                         + "at most 0.8 %1, so they can't be staked directly. Your BlendZk key:")
                    .arg(Units.SYMBOL)
            copyValue: root.blend.zkKey
        }

        BlendCoreRequirement {
            id: addressReq
            objectName: "gateAddress"
            ok: root.blend.checked(root.blend.addressOk)
            label: qsTr("Public address")
            value: root.blend.hostValue.length > 0 ? root.blend.hostValue + ":" + root.blend.portText
                 : root.blend.addressOk === false ? qsTr("not set") : ""
            fix: root.blend.addressProblem
            detail: qsTr("Other Blend nodes dial this address. Joining publishes it "
                         + "on-chain, permanently, for anyone to see.")
                    + "\n\n"
                    + (root.blend.fromConfig
                       ? qsTr("The IP is the one set in your config file.")
                       : qsTr("The IP is the one your node's peers see you at, so it "
                              + "follows your connection."))
                    + " "
                    + qsTr("To set the IP yourself, add a static address under "
                           + "network.backend.swarm.nat in your config file (type: "
                           + "static, external_address: /ip4/<public IP>/udp/3000/quic-v1). "
                           + "The port is root.blend.core.backend.listening_address. Restart "
                           + "the node afterwards. Your config file:")
            copyValue: root.blend.configPath
        }

        BlendCoreRequirement {
            objectName: "gateReachable"
            ok: root.blend.checked(root.blend.reachOk)
            label: qsTr("UDP %1 reachable").arg(root.blend.portText || root.blend.localPort || 3400)
            value: !root.blend.apiAvailable ? (root.blend.attested ? qsTr("confirmed") : "")
                 : root.blend.reachOk === true ? qsTr("open")
                 : root.blend.reachOk === false ? qsTr("closed") : ""
            fix: qsTr("Forward inbound UDP %1 to this machine on your router. The app "
                        + "can't open it — see the guide.")
                   .arg(root.blend.portText || root.blend.localPort || 3400)
            detail: qsTr("The node asks its peers to dial back on this port. Allow it "
                         + "through this machine's firewall too.")
                    + (root.blend.apiAvailable ? ""
                       : " " + qsTr("This node can't run that check yet, so a blocked "
                                    + "port only shows after joining, as missing "
                                    + "activity."))
            linkText: qsTr("Port-forward guide")
            linkValue: root.blend.docsUrl

            LogosCheckbox {
                objectName: "blendAttestCheckbox"
                visible: !root.blend.apiAvailable && root.blend.nodeRunning
                text: qsTr("I've forwarded UDP %1 to this machine")
                      .arg(root.blend.portText || root.blend.localPort || 3400)
                checked: root.blend.attested
                onToggled: root.blend.attested = checked
            }
        }

        BlendCoreRequirement {
            objectName: "gateNetwork"
            // A node that can't report it would spin forever.
            visible: root.blend.apiAvailable
            ok: root.blend.checked(root.blend.networkOk)
            label: qsTr("Blend network size")
            value: root.blend.networkOk === null ? ""
                 : qsTr("%1 providers").arg(root.blend.blendStatus.network_size)
            fix: qsTr("Needs at least %1 active providers on the network.")
                 .arg(root.blend.requirements.minimum_network_size)
            detail: qsTr("Below that, the network pays no rewards.")
        }
    }

    // ================= confirm =================
    ColumnLayout {
        id: confirmPage
        objectName: "blendConfirm"
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !root.blend.declared && root.blend.page === "confirm"
        spacing: Theme.spacing.small

        LogosFrame {
            Layout.fillWidth: true
            backgroundColor: Theme.palette.surfaceRaised
            borderColor: "transparent"
            radius: Theme.spacing.radiusMedium

            ColumnLayout {
                id: confirmFacts
                anchors.fill: parent
                spacing: Theme.spacing.small

                Fact { label: qsTr("Stake to lock"); value: Units.format(root.blend.stakeNoteValue) }
                Fact { label: qsTr("Published address"); value: root.blend.locator; mono: true }
                Fact {
                    label: qsTr("Becomes active")
                    value: qsTr("%1 epochs after the declaration lands")
                           .arg(root.blend.requirements.activation_delay_epochs || 2)
                }
            }
        }

        NoteBlock {
            warning: true
            title: qsTr("Your address becomes public, permanently")
            message: qsTr("It's written to the blockchain, linked to this node and its "
                          + "stake. Anyone can see it, and it can't be changed or "
                          + "removed later. Your internet provider can link it to you.")
        }

        NoteBlock {
            title: qsTr("The stake stays locked while you're a core node")
            message: root.blend.apiAvailable
                ? qsTr("Disabling Blend Core later unlocks it %1 epochs after the "
                       + "withdrawal lands.").arg(root.blend.unlockDelay)
                : qsTr("Leaving Blend Core isn't available on this node yet, so the "
                       + "stake can't be unlocked from here.")
        }
    }
}
