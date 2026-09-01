import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

RowLayout {
    id: cell

    property alias text: cellLabel.text
    property bool sortable: true
    property int leftInset: 12
    spacing: 2

    Item { Layout.preferredWidth: cell.leftInset }

    LogosText {
        id: cellLabel
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.primaryText
        font.weight: Theme.typography.weightRegular
    }
    ColumnLayout {
        Layout.fillWidth: false
        visible: cell.sortable
        spacing: 0

        Image {
            source: LogosIcons.triangleUp
            sourceSize.width: 40
            sourceSize.height: 20
            Layout.preferredWidth: 20
            Layout.preferredHeight: 10
            fillMode: Image.PreserveAspectFit
        }
        Image {
            source: LogosIcons.triangleDown
            sourceSize.width: 40
            sourceSize.height: 20
            Layout.preferredWidth: 20
            Layout.preferredHeight: 10
            fillMode: Image.PreserveAspectFit
        }
    }

    Item { Layout.fillWidth: true }
}
