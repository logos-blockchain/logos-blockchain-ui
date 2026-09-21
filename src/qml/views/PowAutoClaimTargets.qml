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

    spacing: Theme.spacing.small

    QtObject {
        id: d

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
            enabled: !root.busy
                     && accountCombo.currentIndex >= 0
                     && d.isDigits(thresholdField.text)
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

            LogosText {
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

            LogosText {
                text: qsTr("to %1").arg(targetRow.threshold)
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosButton {
                text: qsTr("Remove")
                enabled: !root.busy
                onClicked: targetsModel.remove(targetRow.index)
            }
        }
    }
}
