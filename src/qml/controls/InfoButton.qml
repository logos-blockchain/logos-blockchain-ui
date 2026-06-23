import QtQuick
import QtQuick.Controls

import Logos.Theme
import Logos.Controls

// Small circled-"i" help button. Click to toggle a popup with `text`, a short
// description of the operation. Styled to match the other SVG icon buttons.
Item {
    id: root

    property string text: ""

    implicitWidth: 28
    implicitHeight: 28

    Button {
        id: btn
        anchors.fill: parent
        display: AbstractButton.IconOnly
        flat: true
        padding: 4
        icon.source: Qt.resolvedUrl("../icons/info.svg")
        icon.width: 18
        icon.height: 18
        icon.color: (btn.hovered || popup.visible)
            ? Theme.palette.primary
            : Theme.palette.textTertiary
        onClicked: popup.visible ? popup.close() : popup.open()

        ToolTip.visible: btn.hovered && !popup.visible
        ToolTip.text: qsTr("What is this?")
    }

    Popup {
        id: popup
        // Right-aligned to the button, opening downward.
        x: root.width - width
        y: root.height + Theme.spacing.tiny
        width: 300
        padding: Theme.spacing.medium
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            border.color: Theme.palette.border
            border.width: 1
            radius: Theme.spacing.radiusLarge
        }
        contentItem: LogosText {
            text: root.text
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.text
        }
    }
}
