import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Structured view of recent blocks (BlockModel). Newest block is at the top;
// only the latest 100 are retained by the model.
Control {
    id: root

    // --- Public API ---
    required property var blockModel
    property string emptyText: qsTr("No blocks yet...")
    property string filterSlot: ""
    readonly property int matchCount: {
        if (root.filterSlot.length === 0)
            return slotCollector.count
        var n = 0
        for (var i = 0; i < slotCollector.count; ++i) {
            var o = slotCollector.objectAt(i)
            if (o && o.s === root.filterSlot) ++n
        }
        return n
    }

    Instantiator {
        id: slotCollector
        model: root.blockModel
        delegate: QtObject {
            required property var model
            readonly property string s: model.slot !== undefined ? String(model.slot) : ""
        }
    }

    signal copyToClipboard(string text)

    property QtObject d: QtObject {
        id: d

        readonly property int timestampWidth: 180
        readonly property int consensusWidth: 200
        readonly property int txsWidth: 180
        readonly property int chevronWidth: 42

        readonly property int cellPadding: 12
        readonly property int headerHeight: 32
    }

    background: Rectangle {
        color: Theme.palette.background
    }

    LogosFrame {
        anchors.fill: parent
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusLarge

        contentItem: ColumnLayout {
            spacing: 0

            // Header band — the only tinted surface inside the card.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: d.headerHeight
                color: Theme.colors.getColor(Theme.palette.backgroundInset, 0.6)
                radius: Theme.spacing.radiusLarge

                RowLayout {
                    anchors.fill: parent
                    spacing: 0
                    TableHeaderCell {
                        Layout.preferredWidth: d.timestampWidth
                        Layout.fillWidth: false
                        leftInset: d.cellPadding
                        text: qsTr("Timestamp")
                    }
                    TableHeaderCell {
                        Layout.fillWidth: true
                        leftInset: d.cellPadding
                        text: qsTr("Block")
                    }
                    TableHeaderCell {
                        Layout.preferredWidth: d.consensusWidth
                        Layout.fillWidth: false
                        leftInset: d.cellPadding
                        text: qsTr("Consensus")
                    }
                    TableHeaderCell {
                        Layout.preferredWidth: d.txsWidth
                        Layout.fillWidth: false
                        leftInset: d.cellPadding
                        text: qsTr("TXs")
                        sortable: false
                    }
                    Item { Layout.preferredWidth: d.chevronWidth }
                }
            }

            LogosListView {
                id: blocksListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.blockModel
                spacing: 0
                clip: true

                delegate: BlockDelegate {
                    required property var model
                    collapsed: root.filterSlot.length > 0
                               && String(model.slot) !== root.filterSlot
                    forceExpanded: root.filterSlot.length > 0 && !collapsed
                    timestampWidth: d.timestampWidth
                    consensusWidth: d.consensusWidth
                    txsWidth: d.txsWidth
                    chevronWidth: d.chevronWidth
                    rowPadding: d.cellPadding
                    onCopyToClipboard: (text) => root.copyToClipboard(text)
                }

                LogosText {
                    // ListView's `count` has a NOTIFY signal, unlike the remoted
                    // model's own count property — use it for the empty state.
                    visible: root.matchCount === 0
                    anchors.centerIn: parent
                    text: root.filterSlot.length > 0 && blocksListView.count > 0
                          ? qsTr("Slot %1 isn't in this session's blocks.").arg(root.filterSlot)
                          : root.emptyText
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }
        }
    }
}
