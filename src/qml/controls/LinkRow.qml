import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A HashRow whose value is a link.
RowLayout {
    id: root

    property string label: ""
    property string value: ""
    property int labelWidth: 64
    property bool underline: false

    signal activated()

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Theme.spacing.small

    LogosText {
        visible: root.label.length > 0
        text: root.label
        Layout.preferredWidth: root.labelWidth
        Layout.alignment: Qt.AlignVCenter
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }

    LogosLink {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: root.value
        underline: root.underline
        elide: Text.ElideMiddle
        font.pixelSize: Theme.typography.secondaryText
        font.family: Theme.typography.mono
        onActivated: root.activated()
    }

    LogosCopyButton {
        visible: root.value.length > 0
        value: root.value
    }
}
