import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// One option in an either/or choice, as a card rather than a radio button. The
// routes through setup differ in what they commit the user to, not just in a
// value, so each needs room to say what picking it means.
//
// Shape is the prototype's: heading and body on the left, a tick on the right,
// and a border that does NOT change with selection — the tick is what carries
// it, so the card does not also have to shout.
LogosFrame {
    id: root

    property string title: ""
    property string description: ""
    property string badge: ""
    property bool selected: false

    signal picked()

    Layout.fillWidth: true
    radius: Theme.spacing.radiusLarge
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: Theme.palette.border
    padding: 0

    contentItem: Item {
        implicitWidth: row.implicitWidth + 2 * Theme.spacing.large
        implicitHeight: row.implicitHeight + 2 * Theme.spacing.large

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: root.title
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.primaryText
                        font.weight: Theme.typography.weightBold
                    }

                    LogosBadge {
                        visible: root.badge.length > 0
                        text: root.badge
                        color: Theme.palette.success
                    }

                    Item { Layout.fillWidth: true }
                }

                LogosText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.description
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }
            }

            LogosRadioButton {
                objectName: "choiceIndicator"
                Layout.alignment: Qt.AlignVCenter
                checked: root.selected
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.picked()
        }
    }
}
