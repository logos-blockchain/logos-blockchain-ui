import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// One row of the accounts list. AccountSummary draws it; this adds the row
// surface and the copy button.
LogosItemDelegate {
    id: root

    signal copyRequested(string text)

    readonly property string address: model.address || ""

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)

    focusPolicy: Qt.NoFocus
    background: Rectangle {
        color: Theme.palette.surfaceRecessed
        radius: Theme.spacing.radiusMedium
    }

    contentItem: RowLayout {
        spacing: Theme.spacing.small

        AccountSummary {
            Layout.fillWidth: true
            keyName: model.name || ""
            roleLabel: model.roleLabel || ""
            address: root.address
            balance: model.balance || ""
        }

        LogosCopyButton {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 40
            Layout.preferredWidth: 40
            value: root.address
        }
    }
}
