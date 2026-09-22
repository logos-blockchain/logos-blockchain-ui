pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "infoContent.js" as InfoContent

// Proof-of-Work setup, shown once the user config exists and before the node has
// ever started. That timing is the point: the node reads every value here once,
// when its PoW service starts, so setting them now avoids a "restart required"
// state entirely.
//
// Everything in the node's pow section is editable here, and all of it is
// written by one powConfigure call on Confirm. The defaults are what a desktop
// node wants, so an operator who does not care can pass straight through; the
// fields exist because the node offers no runtime setter for any of them, which
// makes this the only moment before start() when they can be changed.
ColumnLayout {
    id: root

    // --- Public API ---

    // Accounts as plain rows — { address, roles, roleLabel, label } — composed
    // by the backend from the same code that fills the shared AccountsModel.
    // Rows rather than that model because a combo box reads its model once as
    // the popup opens, and the model arrives as a QtRO replica that fills in
    // row data afterwards: the first open would be empty.
    property var accounts: []
    property string defaultThreshold: "100000000"
    property bool busy: false

    // Defaults for the editable mining settings. 
    property int maxThreads: 1
    property int maxTicketsPerBlock: 2
    property int claimTickSeconds: 300
    readonly property int ticketsPerBlockSafeMax: 2

    property bool embedded: false
    readonly property bool valid: d.miningSettingsValid()
    function configJson() { return d.buildConfigJson() }

    spacing: Theme.spacing.medium

    QtObject {
        id: d


        // The validator is the rule; acceptableInput is it being asked. The node
        // types the mining counts as non-zero integers, so a 0 is a
        // deserialization error it only reports at startup — IntValidator's
        // bottom catches it here instead.
        function miningSettingsValid() {
            return maxThreadsField.textInput.acceptableInput
                && maxTicketsField.textInput.acceptableInput
                && claimTickField.textInput.acceptableInput
        }


        // The whole PoW section in one object, which is what powConfigure takes.
        // The mining knobs go with the targets rather than being written
        // separately, so what this screen displays and what lands in the file
        // cannot drift apart.
        function buildConfigJson() {
            return JSON.stringify({
                max_threads: parseInt(maxThreadsField.text),
                max_tickets_per_block: parseInt(maxTicketsField.text),
                tick_seconds: parseInt(claimTickField.text),
                auto_claim_targets: []
            })
        }

    }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        visible: !root.embedded
        font.bold: true
        text: qsTr("Proof of Work")
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
        visible: !root.embedded
        text: qsTr("Mining searches for tickets your node can redeem for rewards. These "
                   + "settings are read once when the node starts, so they are set here "
                   + "rather than while it is running.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }

    // --- Mining settings ----------------------------------------------------

    LogosText {
        Layout.alignment: Qt.AlignLeft
        visible: root.embedded
        text: qsTr("Mining settings")
        color: Theme.palette.text
        font.pixelSize: Theme.typography.secondaryText
        font.weight: Theme.typography.weightMedium
    }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        visible: !root.embedded
        text: qsTr("Mining")
        font.pixelSize: Theme.typography.secondaryText
        font.weight: Theme.typography.weightMedium
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Search threads")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosTextField {
            id: maxThreadsField
            objectName: "powMaxThreadsField"
            Layout.preferredWidth: 90.
            Component.onCompleted: text = String(root.maxThreads)
            validator: IntValidator { bottom: 1 }
        }
        LogosInfoButton {
            title: qsTr("Search threads")
            dialogContentItem: InfoSections { info: InfoContent.powSearchThreads }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Tickets in flight per block")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosTextField {
            id: maxTicketsField
            objectName: "powMaxTicketsField"
            Layout.preferredWidth: 90
            Component.onCompleted: text = String(root.maxTicketsPerBlock)
            validator: IntValidator { bottom: 1 }
        }
        LogosInfoButton {
            title: qsTr("Tickets in flight per block")
            dialogContentItem: InfoSections { info: InfoContent.powTicketsPerBlock }
        }
    }

    // Negative top margin so the caution stays attached to the field it is about,
    // rather than floating at the form's own row spacing between two settings.
    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
        objectName: "powTicketsPerBlockWarning"
        visible: maxTicketsField.textInput.acceptableInput
                 && parseInt(maxTicketsField.text) > root.ticketsPerBlockSafeMax
        text: qsTr("Above %1 the claim batch is likely to exceed what one Blend payload "
                   + "can carry, in which case every claim is rejected and the tickets "
                   + "expire. Measured from a single failure, so it is a caution rather "
                   + "than a known limit.").arg(root.ticketsPerBlockSafeMax)
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.warning
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Claim attempt period (seconds)")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosTextField {
            id: claimTickField
            objectName: "powClaimTickField"
            Layout.preferredWidth: 90
            Component.onCompleted: text = String(root.claimTickSeconds)
            validator: IntValidator { bottom: 1 }
        }
        LogosInfoButton {
            title: qsTr("Claim attempt period")
            dialogContentItem: InfoSections { info: InfoContent.powClaimPeriod }
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
        objectName: "powMiningFieldError"
        visible: !d.miningSettingsValid()
        text: qsTr("Search threads, tickets per block and the claim period must each be "
                   + "a whole number of at least 1.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.error
        wrapMode: Text.WordWrap
    }

}
