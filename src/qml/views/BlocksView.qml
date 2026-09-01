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

    signal clearRequested()
    signal copyToClipboard(string text)

    property QtObject d: QtObject {
        id: d

        readonly property int timestampWidth: 180
        readonly property int consensusWidth: 200
        readonly property int txsWidth: 180
        readonly property int chevronWidth: 42

        readonly property int cellPadding: 12
        readonly property int headerHeight: 36
    }

    background: Rectangle {
        color: Theme.palette.background
    }

    LogosFrame {
        anchors.fill: parent
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusXlarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.large

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 40
                spacing: Theme.spacing.large

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: tabs.bottom
                        height: tabs.indicatorHeight
                        color: Theme.palette.borderTertiaryMuted
                    }

                    LogosTabBar {
                        id: tabs
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: implicitWidth
                        trackColor: "transparent"
                        LogosTabButton {
                            text: qsTr("Blocks")
                            iconSource: Qt.resolvedUrl("../icons/blocks.svg")
                        }
                    }
                }

                LogosButton {
                    text: qsTr("Clear")
                    onClicked: root.clearRequested()
                }
            }

            // ---- Table ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                        visible: blocksListView.count === 0
                        anchors.centerIn: parent
                        text: qsTr("No blocks yet...")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                }
            }
        }
    }
}
