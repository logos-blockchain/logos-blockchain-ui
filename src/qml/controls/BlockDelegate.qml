import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Collapsible card for a single block (BlockModel row).
//   Collapsed: timestamp · slot · version · tx count
//   Expanded:  header hashes, proof-of-leadership group, transactions list
// Unparsed payloads fall back to showing their raw text.
Rectangle {
    id: del

    signal copyToClipboard(string text)

    property bool expanded: false
    property bool proofExpanded: false

    // The transactions role is a QStringList; surface it for the Repeater.
    readonly property var transactionsList: model.transactions || []

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: col.implicitHeight + 2 * Theme.spacing.medium

    color: Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.color: Theme.palette.border
    border.width: 1

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.medium
        spacing: Theme.spacing.small

        // ---- Summary row (always visible, toggles expansion) ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                text: del.expanded ? "▾" : "▸"
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosText {
                text: model.timestamp || ""
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            LogosText {
                visible: model.parsed
                text: qsTr("slot %1").arg(model.slot || qsTr("?"))
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            // Version badge
            Rectangle {
                visible: model.parsed && (model.version || "").length > 0
                radius: Theme.spacing.radiusSmall
                color: Theme.palette.backgroundSecondary
                border.color: Theme.palette.border
                border.width: 1
                implicitWidth: versionText.implicitWidth + 2 * Theme.spacing.small
                implicitHeight: versionText.implicitHeight + Theme.spacing.tiny
                LogosText {
                    id: versionText
                    anchors.centerIn: parent
                    text: model.version || ""
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }

            LogosText {
                visible: !model.parsed
                text: qsTr("Unparsed block")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.warning
            }

            Item { Layout.fillWidth: true }

            LogosText {
                visible: model.parsed
                text: qsTr("%1 tx").arg(model.txCount || 0)
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            TapHandler { onTapped: del.expanded = !del.expanded }
        }

        // ---- Expanded details ----
        ColumnLayout {
            Layout.fillWidth: true
            visible: del.expanded
            spacing: Theme.spacing.small

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // Parsed: structured header
            HashRow { label: qsTr("Parent block"); value: model.parentBlock || ""; visible: model.parsed }
            HashRow { label: qsTr("Block root");   value: model.blockRoot || "";   visible: model.parsed }
            HashRow { label: qsTr("Signature");    value: model.signature || "";   visible: model.parsed }

            // Proof of leadership (collapsible sub-group)
            RowLayout {
                Layout.fillWidth: true
                visible: model.parsed
                spacing: Theme.spacing.small
                LogosText {
                    text: (del.proofExpanded ? "▾ " : "▸ ") + qsTr("Proof of leadership")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                TapHandler { onTapped: del.proofExpanded = !del.proofExpanded }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacing.medium
                visible: model.parsed && del.proofExpanded
                spacing: Theme.spacing.small
                HashRow { label: qsTr("Leader key"); value: model.leaderKey || "" }
                HashRow { label: qsTr("Entropy");    value: model.entropy || "" }
                HashRow { label: qsTr("Proof");      value: model.proof || "" }
                HashRow { label: qsTr("Voucher cm"); value: model.voucherCm || "" }
            }

            // Transactions
            LogosText {
                visible: model.parsed
                text: qsTr("Transactions (%1)").arg(model.txCount || 0)
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: model.parsed
                spacing: Theme.spacing.tiny

                Repeater {
                    model: del.expanded ? del.transactionsList : []
                    delegate: TxItem {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        idx: index
                        json: modelData
                    }
                }

                LogosText {
                    visible: (model.txCount || 0) === 0
                    text: qsTr("No transactions in this block.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            // Unparsed: raw fallback
            RowLayout {
                Layout.fillWidth: true
                visible: !model.parsed
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Raw payload")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                LogosCopyButton { onCopyText: del.copyToClipboard(model.rawJson || "") }
            }
            JsonBlock {
                Layout.fillWidth: true
                visible: !model.parsed
                json: model.rawJson || ""
            }
        }
    }

    // ---- Inline helpers ----

    component HashRow: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: label
            Layout.preferredWidth: 110
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            text: value && value.length > 0 ? value : "—"
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
            font.family: "monospace"
        }
        LogosCopyButton {
            visible: value && value.length > 0
            onCopyText: del.copyToClipboard(value)
        }
    }

    component JsonBlock: Rectangle {
        property string json
        implicitHeight: jsonText.implicitHeight + 2 * Theme.spacing.small
        color: Theme.palette.backgroundSecondary
        radius: Theme.spacing.radiusSmall
        border.color: Theme.palette.border
        border.width: 1
        LogosText {
            id: jsonText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacing.small
            text: parent.json
            font.pixelSize: Theme.typography.secondaryText
            font.family: "monospace"
            wrapMode: Text.WrapAnywhere
        }
    }

    component TxItem: ColumnLayout {
        id: txRoot
        property int idx
        property string json
        property bool open: false
        spacing: Theme.spacing.tiny

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                text: (txRoot.open ? "▾ " : "▸ ") + qsTr("Transaction %1").arg(txRoot.idx + 1)
                font.pixelSize: Theme.typography.secondaryText
                TapHandler { onTapped: txRoot.open = !txRoot.open }
            }
            Item { Layout.fillWidth: true }
            LogosCopyButton { onCopyText: del.copyToClipboard(txRoot.json) }
        }
        JsonBlock {
            Layout.fillWidth: true
            visible: txRoot.open
            json: txRoot.json
        }
    }
}
