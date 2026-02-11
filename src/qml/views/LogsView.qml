import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.DesignSystem

import controls

Control {
    id: root

    // --- Public API ---
    required property var logModel   // LogModel (QAbstractListModel with "text" role)

    signal clearRequested()

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

            Text {
                text: qsTr("Logs")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
                color: Theme.palette.text
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

                delegate: Text {
                    text: model.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.family: Theme.typography.publicSans
                    color: Theme.palette.text
                    width: logsListView.width
                    wrapMode: Text.Wrap
                }

                Text {
                    visible: !root.logModel || root.logModel.count === 0
                    anchors.centerIn: parent
                    text: qsTr("No logs yet...")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }

                Connections {
                    target: root.logModel
                    function onCountChanged() {
                        if (root.logModel.count > 0)
                            logsListView.positionViewAtEnd()
                    }
                }
            }
        }
    }
}
