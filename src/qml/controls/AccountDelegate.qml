import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

LogosItemDelegate {
    id: root

    property string balanceError: ""
    property bool refreshing: false

    signal getBalanceRequested(string addressHex)
    signal copyRequested(string text)

    width: ListView.view ? ListView.view.width : implicitWidth
    hoverColor: Theme.palette.backgroundSecondary
    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                Layout.fillWidth: true
                text: model.address || ""
                elide: Text.ElideMiddle
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosText {
                Layout.preferredWidth: contentWidth
                Layout.alignment: Qt.AlignRight
                visible: (model.balance || "").length > 0
                text: model.balance || ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                elide: Text.ElideRight
            }

            Item {
                Layout.alignment: Qt.AlignRight
                Layout.leftMargin: parent.spacing
                Layout.preferredHeight: 40
                Layout.preferredWidth: 40

                LogosSpinner {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    visible: root.refreshing
                    running: root.refreshing
                    ringColor: Theme.palette.textTertiary
                }

                LogosIconButton {
                    id: refreshButton
                    anchors.fill: parent
                    visible: !root.refreshing
                    flat: true
                    size: 40
                    iconSize: 20
                    iconSource: LogosIcons.refresh
                    iconColor: refreshButton.isActive ? Theme.palette.text
                                                      : Theme.palette.textTertiary
                    onClicked: root.getBalanceRequested(model.address || "")
                }
            }

            LogosCopyButton {
                Layout.alignment: Qt.AlignRight
                Layout.preferredHeight: 40
                Layout.preferredWidth: 40
                value: model.address || ""
            }
        }

        LogosText {
            Layout.fillWidth: true
            visible: !!text
            text: root.balanceError || ""
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
            wrapMode: Text.WordWrap
        }
    }
}
