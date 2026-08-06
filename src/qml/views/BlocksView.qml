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

    background: Rectangle {
        color: Theme.palette.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacing.large
        spacing: Theme.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: Theme.spacing.medium

            LogosText {
                text: qsTr("Blocks")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            LogosButton {
                text: qsTr("Clear")
                onClicked: root.clearRequested()
            }
        }

        // Block list
        LogosFrame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: Theme.spacing.small
            backgroundColor: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge

            contentItem: LogosListView {
                id: blocksListView
                model: root.blockModel
                spacing: Theme.spacing.small

                delegate: BlockDelegate {
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
