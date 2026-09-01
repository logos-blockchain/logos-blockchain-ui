import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

LogosFrame {
    id: root

    property string label: ""
    property string value: "—"
    property string info: ""

    padding: Theme.spacing.large
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: "transparent"
    radius: Theme.spacing.radiusXlarge

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium

        LogosText {
            Layout.fillWidth: true
            text: root.value
            color: Theme.palette.textSecondary
            font.pixelSize: 38
            font.weight: Theme.typography.weightRegular
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.palette.borderTertiaryMuted
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 32
            spacing: Theme.spacing.small

            LogosText {
                Layout.fillWidth: true
                text: root.label
                color: Theme.palette.text
                font.pixelSize: Theme.typography.subtitleText
                font.weight: Theme.typography.weightMedium
                elide: Text.ElideRight
            }

            InfoButton {
                visible: root.info.length > 0
                text: root.info
            }
        }
    }
}
