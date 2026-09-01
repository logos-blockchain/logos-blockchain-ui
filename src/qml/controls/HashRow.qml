import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A labelled value row with an elided monospace value and a copy button.
// Used for hashes/keys and any short scalar field.
RowLayout {
    id: root

    property string label: ""
    property string value: ""
    property int labelWidth: 110
    property bool copyable: true

    // Overridable so the chain-stats card can use the design's larger TiP/LiB
    // label without changing every other caller.
    property int labelPixelSize: Theme.typography.secondaryText
    property int valuePixelSize: Theme.typography.secondaryText
    property color labelColor: Theme.palette.textSecondary
    property int labelWeight: Theme.typography.weightRegular

    // Optional qualifier shown after the label, e.g. the slot a hash belongs to.
    property string note: ""

    signal copyRequested(string text)

    Layout.fillWidth: true
    spacing: Theme.spacing.small

    LogosText {
        visible: root.label.length > 0
        text: root.label
        Layout.preferredWidth: root.labelWidth
        Layout.alignment: Qt.AlignVCenter
        color: root.labelColor
        font.pixelSize: root.labelPixelSize
        font.weight: root.labelWeight
    }
    LogosText {
        visible: root.note.length > 0
        text: root.note
        Layout.alignment: Qt.AlignVCenter
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
    }
    LogosText {
        Layout.fillWidth: true
        text: root.value && root.value.length > 0 ? root.value : "—"
        elide: Text.ElideMiddle
        font.pixelSize: root.valuePixelSize
        font.family: Theme.typography.mono
    }
    LogosCopyButton {
        visible: root.copyable && root.value && root.value.length > 0
        value: root.value
    }
}
