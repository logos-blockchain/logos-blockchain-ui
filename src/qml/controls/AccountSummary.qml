import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// How an account reads: what it is called and its address on the left, its
// balance on the right. The copy button, when shown, sits beside the address it
// copies rather than beside the balance.
RowLayout {
    id: root

    property string keyName: ""    // from the keystore; titles every key
    property string roleLabel: ""  // from the config; titles only the wired ones
    property string address: ""
    property string balance: ""    // lepta, as the node reports it
    property bool copyable: false

    readonly property string title: keyName.length > 0 ? keyName : roleLabel
    readonly property bool titled: title.length > 0

    spacing: Theme.spacing.large

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Theme.spacing.tiny

        LogosText {
            Layout.fillWidth: true
            visible: root.titled
            text: root.title
            elide: Text.ElideRight
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightBold
        }

        // Untitled, the address is the headline and takes the title's weight.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.tiny

            LogosText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.maximumWidth: implicitWidth
                text: root.address
                elide: Text.ElideMiddle
                font.pixelSize: Theme.typography.secondaryText
                font.weight: root.titled ? Theme.typography.weightRegular
                                         : Theme.typography.weightBold
                color: root.titled ? Theme.palette.textSecondary : Theme.palette.text
            }

            LogosCopyButton {
                Layout.alignment: Qt.AlignVCenter
                visible: root.copyable && root.address.length > 0
                value: root.address
            }

            Item { Layout.fillWidth: true }
        }
    }

    LogosText {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        visible: text.length > 0
        text: Units.format(root.balance)
        font.pixelSize: Theme.typography.primaryText
    }
}
