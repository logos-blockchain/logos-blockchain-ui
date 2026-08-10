import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Live Blend Network participation for this node, shown under the Consensus block.
// Mirrors CryptarchiaInfoView's card: a "Blend" label on the left, the current
// state on the right (blue while actively mixing), and a per-epoch detail line.
Rectangle {
    id: root

    property string statusText: ""     // "edge" / "core" / "broadcast" / "inactive" / ...
    property color  statusColor: Theme.palette.textSecondary
    property string eventText: ""      // honest per-epoch detail (verbatim on errors)

    implicitHeight: contentCol.implicitHeight + 2 * Theme.spacing.large
    color: Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.color: Theme.palette.border
    border.width: 1

    ColumnLayout {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.large
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                text: qsTr("Blend")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            LogosText {
                text: root.statusText
                color: root.statusColor
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
        }

        LogosText {
            Layout.fillWidth: true
            visible: root.eventText.length > 0
            text: root.eventText
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            wrapMode: Text.WordWrap
        }
    }
}
