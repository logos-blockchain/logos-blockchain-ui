import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Control {
    id: root

    // --- Public API ---
    required property var logModel   // ListModel with "text" role

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
                text: qsTr("Logs")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            LogosButton {
                text: qsTr("Clear")
                Layout.preferredWidth: 80
                Layout.preferredHeight: 32
                onClicked: root.clearRequested()
            }
        }

        // Log list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1

            ListView {
                id: logsListView
                anchors.fill: parent
                clip: true
                model: root.logModel
                spacing: 2

                // Auto-scroll to the latest log on insert. Use the ListView's
                // own `count` (it's always available and emits countChanged) —
                // the model replica is a QAbstractItemModelReplica and does
                // not carry the source-side `count` Q_PROPERTY through QtRO.
                onCountChanged: if (count > 0) positionViewAtEnd()

                delegate: ItemDelegate{
                    width: ListView.view.width
                    contentItem: LogosText {
                        text: model.text
                        font.pixelSize: Theme.typography.secondaryText
                        wrapMode: Text.Wrap
                    }
                    background: Rectangle {
                        color: hovered ? Theme.palette.background: "transparent"
                        radius: 2
                    }
                    onClicked: root.copyToClipboard(model.text)
                }

                LogosText {
                    // ListView's `count` reflects the model row count and has
                    // a NOTIFY signal — using it here gives the binding
                    // automatic refresh, unlike `root.logModel.count`.
                    visible: logsListView.count === 0
                    anchors.centerIn: parent
                    text: qsTr("No logs yet...")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }
        }
    }
}
