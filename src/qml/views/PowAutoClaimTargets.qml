pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "infoContent.js" as InfoContent

// The accounts auto-claim pays into, and the only thing that turns auto-claim
// on: the node arms it at startup precisely when pow.auto_claim.targets is
// non-empty.
ColumnLayout {
    id: root

    // Rows { address, roles, roleLabel, label } from the config's wallet keys.
    property var accounts: []
    property var initialTargets: []
    property string defaultThreshold: "100000000"
    property bool busy: false

    // Non-empty is exactly "auto-claim is on", which is why the step gates on it.
    readonly property int targetCount: targetsModel.count

    // The list as powConfigure takes it.
    function targets() {
        var out = []
        for (var i = 0; i < targetsModel.count; ++i) {
            out.push({
                public_key: targetsModel.get(i).publicKey,
                threshold: targetsModel.get(i).threshold
            })
        }
        return out
    }

    Component.onCompleted: {
        d.seeded = true
        d.seed()
    }
    onInitialTargetsChanged: if (d.seeded) d.seed()
    onAccountsChanged: if (d.seeded) d.relabel()

    spacing: Theme.spacing.small

    QtObject {
        id: d

        readonly property string noCapThreshold: "18446744073709551615"

        readonly property int accountColumnWidth: 260

        // `initialTargets` is bound from the parent, so its change signal fires
        // DURING creation — before the ListModel below is built — and seeding
        // then reaches an object that is not there yet.
        property bool seeded: false

        function thresholdLabel(value) {
            return value === d.noCapThreshold ? qsTr("No cap") : qsTr("to %1").arg(value)
        }

        function labelFor(publicKey) {
            for (var i = 0; i < root.accounts.length; ++i) {
                if (root.accounts[i] && root.accounts[i].address === publicKey)
                    return root.accounts[i].label || ""
            }
            return ""
        }

        function relabel() {
            for (var i = 0; i < targetsModel.count; ++i)
                targetsModel.setProperty(i, "label", d.labelFor(targetsModel.get(i).publicKey))
        }

        function seed() {
            targetsModel.clear()
            for (var i = 0; i < root.initialTargets.length; ++i) {
                const t = root.initialTargets[i]
                if (!t || !t.public_key)
                    continue
                targetsModel.append({
                    publicKey: t.public_key,
                    label: d.labelFor(t.public_key),
                    threshold: String(t.threshold)
                })
            }
        }

        function isDigits(text) { return /^[0-9]+$/.test(text) }

        function alreadyAdded(key) {
            for (var i = 0; i < targetsModel.count; ++i) {
                if (targetsModel.get(i).publicKey === key)
                    return true
            }
            return false
        }

        function addTarget() {
            const key = accountCombo.currentValue
            const capped = !noCapSwitch.checked
            if (!key || key === "" || alreadyAdded(key) || (capped && !isDigits(thresholdField.text)))
                return
            targetsModel.append({
                publicKey: key,
                label: accountCombo.currentText,
                threshold: capped ? thresholdField.text : d.noCapThreshold
            })
            accountCombo.currentIndex = -1
            thresholdField.text = root.defaultThreshold
        }
    }

    ListModel { id: targetsModel }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Pays into")
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightMedium
        }

        Item { Layout.fillWidth: true }

        LogosInfoButton {
            title: qsTr("Auto-claim targets")
            dialogContentItem: InfoSections { info: InfoContent.powAutoClaimTargets }
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: qsTr("Threshold is the balance an account should reach — not an amount to pay. "
                   + "Once an account is at or above it, the node stops paying that one.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosComboBox {
            id: accountCombo
            objectName: "powAccountCombo"
            Layout.preferredWidth: d.accountColumnWidth
            placeholderText: qsTr("Account…")
            model: root.accounts
            textRole: "label"
            valueRole: "address"
            currentIndex: -1
        }

        LogosText {
            text: qsTr("No cap")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        LogosSwitch {
            id: noCapSwitch
            objectName: "powNoCapSwitch"
            checked: false
        }

        LogosTextField {
            id: thresholdField
            objectName: "powThresholdField"
            Layout.fillWidth: true
            visible: !noCapSwitch.checked
            text: root.defaultThreshold
            placeholderText: qsTr("Target balance")
        }

        Item {
            Layout.fillWidth: true
            visible: noCapSwitch.checked
        }

        LogosButton {
            objectName: "powAddTargetButton"
            text: qsTr("Add")
            enabled: !root.busy
                     && accountCombo.currentIndex >= 0
                     && (noCapSwitch.checked || d.isDigits(thresholdField.text))
                     && !d.alreadyAdded(accountCombo.currentValue)
            onClicked: d.addTarget()
        }
    }

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

            RowLayout {
                Layout.preferredWidth: d.accountColumnWidth
                Layout.maximumWidth: d.accountColumnWidth
                spacing: Theme.spacing.small

                LogosText {
                    visible: targetRow.label.length > 0
                    text: targetRow.label
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }

                LogosText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: targetRow.publicKey
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideMiddle
                }
            }

            LogosText {
                text: d.thresholdLabel(targetRow.threshold)
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            Item { Layout.fillWidth: true }

            LogosButton {
                text: qsTr("Remove")
                enabled: !root.busy
                onClicked: targetsModel.remove(targetRow.index)
            }
        }
    }
}
