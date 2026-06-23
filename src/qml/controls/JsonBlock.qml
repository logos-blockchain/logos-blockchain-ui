import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A boxed, monospace, wrapping JSON/text block. Used for prettified payloads
// and raw fallbacks.
Rectangle {
    id: root

    property string json: ""

    Layout.fillWidth: true
    implicitHeight: jsonText.implicitHeight + 2 * Theme.spacing.small
    color: Theme.palette.backgroundSecondary
    radius: Theme.spacing.radiusSmall
    border.color: Theme.palette.border
    border.width: 1

    LogosText {
        id: jsonText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.small
        text: root.json
        font.pixelSize: Theme.typography.secondaryText
        font.family: "monospace"
        wrapMode: Text.WrapAnywhere
    }
}
