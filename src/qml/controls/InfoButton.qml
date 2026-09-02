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

    LogosIconButton {
        id: btn
        anchors.fill: parent
        flat: true
        size: 28
        iconSize: 18
        iconSource: Qt.resolvedUrl("../icons/info.svg")
        iconColor: (btn.hovered || popup.visible)
            ? Theme.palette.primary
            : Theme.palette.textTertiary
        onClicked: popup.visible ? popup.close() : popup.open()

        // Short hover hint. The wrapping body text lives in `popup` — a
        // LogosToolTip is a single-line tip and won't wrap a paragraph.
        LogosToolTip {
            text: qsTr("What is this?")
            placement: LogosToolTip.Placement.Top
            visible: btn.hovered && !popup.visible
        }
    }

    Popup {
        id: popup
        y: root.height + Theme.spacing.tiny
        margins: Theme.spacing.small

        onAboutToShow: {
            const desired = root.width - width
            const overhang = Theme.spacing.small - root.mapToItem(null, desired, 0).x
            popup.x = overhang > 0 ? desired + overhang : desired
        }
        width: 300
        padding: Theme.spacing.medium
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: LogosFrame {
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
