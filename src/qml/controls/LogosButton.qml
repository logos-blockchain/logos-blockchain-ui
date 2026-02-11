import QtQuick
import QtQuick.Controls

import Logos.DesignSystem

Button {
    implicitWidth: 200
    implicitHeight: 50

    background: Rectangle {
        color: parent.pressed || parent.hovered ?
                   Theme.palette.backgroundMuted :
                   Theme.palette.backgroundSecondary
        radius: Theme.spacing.radiusXlarge
        border.color: parent.pressed || parent.hovered ?
                          Theme.palette.overlayOrange :
                          Theme.palette.border
        border.width: 1
    }
}
