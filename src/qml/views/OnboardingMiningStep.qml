import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Step 4: mining, which on this chain is how a fresh node funds itself. The
// node reads its whole pow section once, when its PoW service starts, so this
// is the last moment before the first start when any of it can be set without
// a restart — which is the only reason it is in the wizard at all.
ColumnLayout {
    id: root

    property var accounts: []
    property var powSection: ({})
    readonly property var existingTargets:
        (powSection && powSection.auto_claim_targets) ? powSection.auto_claim_targets : []
    property bool busy: false
    property string errorMessage: ""
    readonly property bool configureMining: true
    readonly property bool autoClaimOn: autoClaimSwitch.checked
    readonly property bool needsTarget: autoClaimSwitch.checked && targetsView.targetCount === 0
    readonly property bool valid: powForm.valid && !root.needsTarget

    signal submitted(string configJson)

    function submit() {
        var cfg = JSON.parse(powForm.configJson())
        cfg.auto_claim_targets = autoClaimSwitch.checked ? targetsView.targets() : []
        root.submitted(JSON.stringify(cfg))
    }

    spacing: Theme.spacing.medium

    LogosText {
        text: qsTr("Fund your node")
        color: Theme.palette.text
        font.pixelSize: OnboardingText.stepHeading
        font.weight: Theme.typography.weightBold
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: qsTr("A node needs stake before it can propose blocks. Your node can earn that "
                   + "stake itself by mining in the background — no faucet, no manual "
                   + "funding.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosFrame {
        Layout.fillWidth: true
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    text: qsTr("Claim mined rewards automatically")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.primaryText
                    font.weight: Theme.typography.weightMedium
                }

                LogosBadge {
                    objectName: "miningRecommendedBadge"
                    text: qsTr("Recommended")
                    color: Theme.palette.success
                }

                Item { Layout.fillWidth: true }

                LogosSwitch {
                    id: autoClaimSwitch
                    objectName: "autoClaimSwitch"
                    property bool userDecided: false

                    checked: true
                    onToggled: userDecided = true
                }

                Connections {
                    target: root
                    function onExistingTargetsChanged() {
                        if (!autoClaimSwitch.userDecided)
                            autoClaimSwitch.checked = root.existingTargets.length > 0
                    }
                }
            }

            LogosText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: qsTr("Mined tickets have to be claimed before they expire. Leave this "
                           + "on and the node claims them for you, into an account you "
                           + "name below.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            LogosText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: !autoClaimSwitch.checked
                text: qsTr("Off. Mining still works — press Fund on the node screen — and "
                           + "your mining settings below are still written. You claim the "
                           + "rewards yourself from the Rewards tab.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            PowAutoClaimTargets {
                id: targetsView
                initialTargets: root.existingTargets
                objectName: "autoClaimTargets"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                visible: autoClaimSwitch.checked
                accounts: root.accounts
                busy: root.busy
            }
        }
    }

    LogosScrollView {
        id: powScroll
        Layout.fillWidth: true
        Layout.fillHeight: true

        PowConfigView {
            id: powForm
            objectName: "miningPowForm"
            width: powScroll.availableWidth
            embedded: true
            accounts: root.accounts
            busy: root.busy
        }
    }

    Connections {
        target: root
        function onPowSectionChanged() { powForm.loadFrom(root.powSection) }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: qsTr("These are defaults — you can change them any time in the node's config "
                   + "file. Leaving auto-claim targets empty is a valid choice: it simply "
                   + "leaves auto-claim off.")
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosNotice {
        objectName: "miningErrorNotice"
        Layout.fillWidth: true
        shown: root.errorMessage.length > 0
        severity: LogosNotice.Error
        title: qsTr("Could not save the mining settings")
        message: root.errorMessage
        actions: [
            LogosCopyButton { value: root.errorMessage }
        ]
    }

    Item { Layout.fillHeight: true }
}
