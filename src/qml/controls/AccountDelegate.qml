import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

LogosItemDelegate {
    id: root

    signal copyRequested(string text)

    readonly property string keyName: model.name || ""
    readonly property string roleLabel: model.roleLabel || ""
    readonly property string title: keyName.length > 0 ? keyName : roleLabel
    readonly property string address: model.address || ""
    readonly property bool titled: root.title.length > 0

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)

    focusPolicy: Qt.NoFocus
    background: Rectangle {
        color: Theme.palette.surfaceRecessed
        radius: Theme.spacing.radiusMedium
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.tiny

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                id: titleText
                Layout.fillWidth: true
                text: root.titled ? root.title : root.address
                elide: Text.ElideMiddle
                font.pixelSize: Theme.typography.secondaryText
                font.weight: Theme.typography.weightBold

                HoverHandler { id: titleHover; enabled: root.titled }

                LogosToolTip {
                    text: root.roleLabel.length > 0
                          ? qsTr("Used as “%1” in the node config.").arg(root.roleLabel)
                          : qsTr("Held in the keystore; the node config gives it no job.")
                    placement: LogosToolTip.Placement.Top
                    visible: titleHover.hovered
                }
            }

            LogosText {
                Layout.preferredWidth: contentWidth
                Layout.alignment: Qt.AlignVCenter
                visible: (model.balance || "").length > 0
                text: Units.format(model.balance || "")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                elide: Text.ElideRight
            }

            LogosCopyButton {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 40
                Layout.preferredWidth: 40
                value: root.address
            }
        }

        LogosText {
            Layout.fillWidth: true
            visible: root.titled
            text: root.address
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
    }
}
