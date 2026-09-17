pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

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
    property bool resultSuccess: false
    property string resultMessage: ""

    // Defaults for the editable mining settings. 
    property int maxThreads: 1
    property int maxTicketsPerBlock: 2
    property int claimTickSeconds: 300
    readonly property int ticketsPerBlockSafeMax: 2

    // configJson is the whole pow section powConfigure takes. An empty target
    // list is meaningful: it leaves auto-claim off.
    signal confirmRequested(string configJson)

    spacing: Theme.spacing.medium

    QtObject {
        id: d

        // Threshold only. The mining fields answer for themselves through their
        // validators; this one cannot use an IntValidator, because thresholds
        // are u64 and IntValidator tops out at INT_MAX — it would silently
        // refuse a perfectly legal target balance.
        function isDigits(text) { return /^[0-9]+$/.test(text) }

        // The validator is the rule; acceptableInput is it being asked. The node
        // types the mining counts as non-zero integers, so a 0 is a
        // deserialization error it only reports at startup — IntValidator's
        // bottom catches it here instead.
        function miningSettingsValid() {
            return maxThreadsField.textInput.acceptableInput
                && maxTicketsField.textInput.acceptableInput
                && claimTickField.textInput.acceptableInput
        }

        function alreadyAdded(key) {
            for (var i = 0; i < targetsModel.count; ++i) {
                if (targetsModel.get(i).publicKey === key)
                    return true
            }
            return false
        }

        // The whole PoW section in one object, which is what powConfigure takes.
        // The mining knobs go with the targets rather than being written
        // separately, so what this screen displays and what lands in the file
        // cannot drift apart.
        function buildConfigJson() {
            var targets = []
            for (var i = 0; i < targetsModel.count; ++i) {
                targets.push({
                    public_key: targetsModel.get(i).publicKey,
                    threshold: targetsModel.get(i).threshold
                })
            }
            return JSON.stringify({
                max_threads: parseInt(maxThreadsField.text),
                max_tickets_per_block: parseInt(maxTicketsField.text),
                tick_seconds: parseInt(claimTickField.text),
                auto_claim_targets: targets
            })
        }

        // valueRole/currentValue rather than a lookup by index: the model
        // arrives as a remoted replica, which serves rows to delegates but has
        // no get() to call. currentText is the same label the row rendered, so
        // the target records exactly what the operator picked.
        function addTarget() {
            const key = accountCombo.currentValue
            if (!key || key === "" || alreadyAdded(key) || !isDigits(thresholdField.text))
                return
            targetsModel.append({
                publicKey: key,
                label: accountCombo.currentText,
                threshold: thresholdField.text
            })
            accountCombo.currentIndex = -1
            thresholdField.text = root.defaultThreshold
        }
    }

    ListModel { id: targetsModel }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        font.bold: true
        text: qsTr("Proof of Work")
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
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
        text: qsTr("Mining")
        font.pixelSize: Theme.typography.secondaryText
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
            text: qsTr("Worker threads the ticket search may use. Left uncapped the "
                       + "node takes one thread per logical CPU, which makes the "
                       + "machine unusable while mining.")
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
            text: qsTr("How many mined tickets the node carries into one block. Each "
                       + "ticket's claim carries its own proof, so raising this costs "
                       + "twice over.\n\n"
                       + "The whole batch has to fit a single Blend payload, and the "
                       + "node's own default overruns it — claims are then rejected and "
                       + "the tickets expire unclaimed.\n\n"
                       + "Every extra ticket is also another proof to build, and that "
                       + "work lands on the CPU on top of the ticket search itself. "
                       + "Above %1, expect the machine to feel it.").arg(root.ticketsPerBlockSafeMax)
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
            text: qsTr("How often the node tries to pay an auto-claim target. On each "
                       + "attempt it pays the one target holding the least value among "
                       + "those still below their threshold.")
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

    // --- Auto-claim targets -------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Auto-claim targets")
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosInfoButton {
            title: qsTr("Auto-claim targets")
            text: qsTr("Accounts mined rewards are paid into, without you asking. Adding at "
                       + "least one turns auto-claim on: the node arms it at startup whenever "
                       + "the list is not empty. Leave the list empty and rewards are only "
                       + "claimed when you press Claim yourself.\n\n"
                       + "An account must be one the config already tracks, or the node "
                       + "refuses to start.")
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: qsTr("Threshold is the balance an account should reach — not an amount to pay. "
                   + "Once an account is at or above it, the node stops paying that one.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosComboBox {
            id: accountCombo
            objectName: "powAccountCombo"
            Layout.preferredWidth: 260
            placeholderText: qsTr("Account…")
            model: root.accounts
            textRole: "label"
            valueRole: "address"
            currentIndex: -1
        }

        LogosTextField {
            id: thresholdField
            objectName: "powThresholdField"
            Layout.fillWidth: true
            text: root.defaultThreshold
            placeholderText: qsTr("Target balance")
        }

        LogosButton {
            objectName: "powAddTargetButton"
            text: qsTr("Add")
            enabled: targetsModel.count >= 0
                     && !root.busy
                     && accountCombo.currentIndex >= 0
                     && d.isDigits(thresholdField.text)
                     && !d.alreadyAdded(accountCombo.currentValue)
            onClicked: d.addTarget()
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: targetsModel.count === 0
        text: qsTr("No targets yet — auto-claim stays off and you claim rewards manually.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textTertiary
        wrapMode: Text.WordWrap
    }

    // A Repeater rather than a ListView: the row count is small and bounded by
    // the account list, and a ListView inside a ColumnLayout needs a height this
    // form has no good value for.
    Repeater {
        model: targetsModel

        RowLayout {
            id: targetRow

            required property int index
            required property string publicKey
            required property string label
            required property string threshold

            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                text: targetRow.label
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            LogosText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: targetRow.publicKey
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                elide: Text.ElideMiddle
            }
            LogosText {
                text: qsTr("to %1").arg(targetRow.threshold)
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            LogosButton {
                text: qsTr("Remove")
                enabled: !root.busy
                onClicked: targetsModel.remove(targetRow.index)
            }
        }
    }

    // --- Confirm ------------------------------------------------------------

    LogosButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 50
        objectName: "powConfirmButton"
        enabled: !root.busy && d.miningSettingsValid()
        text: root.busy ? qsTr("Saving…")
                        : (targetsModel.count === 0 ? qsTr("Continue without auto-claim")
                                                    : qsTr("Confirm"))
        onClicked: root.confirmRequested(d.buildConfigJson())
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: root.resultMessage !== ""
        text: root.resultMessage
        color: root.resultSuccess ? Theme.palette.success : Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }
}
