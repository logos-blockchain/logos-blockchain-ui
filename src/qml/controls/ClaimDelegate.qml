import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// One settled reward claim, for a ListView over the remoted ClaimsModel.
Rectangle {
    id: root

    // ---- ClaimsModel roles ----
    required property string value
    required property string payee
    required property string txHash
    required property string blockId
    required property var slot
    required property bool confirmed
    required property int slotsToFinality

    // ---- Slot → date. Zero for either means "not reported yet" ----
    property real slotDurationMs: 0
    property real genesisTimeMs: 0

    signal openInExplorerRequested(string id)

    readonly property string finalityText: {
        if (root.slotsToFinality <= 0)
            return qsTr("Finalizing")
        if (root.slotDurationMs <= 0)
            return qsTr("Finalizes in %n slot(s)", "", root.slotsToFinality)
        const seconds = Math.round(root.slotsToFinality * root.slotDurationMs / 1000)
        if (seconds < 90)
            return qsTr("Finalizes in ~%n second(s)", "", seconds)
        const minutes = Math.round(seconds / 60)
        if (minutes < 90)
            return qsTr("Finalizes in ~%n minute(s)", "", minutes)
        return qsTr("Finalizes in ~%n hour(s)", "", Math.round(minutes / 60))
    }

    // A slot is only a date once genesis and the slot length are both known.
    // Without them the row says nothing rather than inventing one.
    readonly property string dateText: {
        if (root.slotDurationMs <= 0 || root.genesisTimeMs <= 0)
            return ""
        const ms = root.genesisTimeMs + Number(root.slot) * root.slotDurationMs
        if (!isFinite(ms))
            return ""
        return new Date(ms).toLocaleString(Qt.locale(), Locale.ShortFormat)
    }

    width: ListView.view ? ListView.view.width : implicitWidth
    height: claimRow.implicitHeight + Theme.spacing.small * 2
    radius: Theme.spacing.radiusSmall
    color: Theme.palette.backgroundSecondary
    border.color: Theme.palette.border
    border.width: 1

    ColumnLayout {
        id: claimRow
        anchors.fill: parent
        anchors.margins: Theme.spacing.small
        spacing: Theme.spacing.tiny

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Theme.spacing.small

            LogosText {
                text: Units.format(root.value)
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
                color: Theme.palette.text
            }

            LogosText {
                visible: root.dateText.length > 0
                text: "·"
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosText {
                visible: root.dateText.length > 0
                text: root.dateText
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }

            Item { Layout.fillWidth: true }

            LogosBadge {
                visible: !root.confirmed
                text: root.finalityText
                backgroundColor: Theme.palette.backgroundTertiary
                borderColor: Theme.palette.warning
                labelItem.color: Theme.palette.warning
                labelItem.font.pixelSize: Theme.typography.secondaryText
            }
        }

        HashRow {
            Layout.fillHeight: false
            label: qsTr("Slot")
            labelWidth: 64
            value: String(root.slot)
        }
        HashRow {
            Layout.fillHeight: false
            label: qsTr("Paid to")
            labelWidth: 64
            value: root.payee
        }
        LinkRow {
            label: qsTr("Tx")
            value: root.txHash
            onActivated: root.openInExplorerRequested(root.txHash)
        }
        LinkRow {
            label: qsTr("Block")
            value: root.blockId
            onActivated: root.openInExplorerRequested(root.blockId)
        }
    }
}
