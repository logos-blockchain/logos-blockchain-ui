import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// How an account reads: what it is called, its address, and its balance
ColumnLayout {
    id: root

    property string keyName: ""    // from the keystore; titles every key
    property string roleLabel: ""  // from the config; titles only the wired ones
    property string address: ""
    property string balance: ""    // lepta, as the node reports it

    readonly property string title: keyName.length > 0 ? keyName : roleLabel
    readonly property bool titled: title.length > 0

    spacing: Theme.spacing.tiny

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosText {
            Layout.fillWidth: true
            text: root.titled ? root.title : root.address
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightBold
        }

        LogosText {
            Layout.preferredWidth: contentWidth
            Layout.alignment: Qt.AlignVCenter
            visible: text.length > 0
            text: Units.format(root.balance)
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            elide: Text.ElideRight
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
