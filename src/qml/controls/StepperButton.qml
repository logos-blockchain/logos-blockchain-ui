import QtQuick

import Logos.Theme
import Logos.Controls

// Small square nudge button, per the design's "Compact Button": near-black fill,
// a thin grey outline, and a light-grey glyph. LogosIconButton draws a circular
// pill instead, which is the wrong shape here.
Rectangle {
    id: root

    property url iconSource: ""
    property bool enabled: true

    signal clicked()

    implicitWidth: 28
    implicitHeight: 28
    radius: Theme.spacing.radiusMedium

    color: Theme.palette.backgroundInset
    border.width: 1
    border.color: Theme.palette.borderTertiaryMuted
    opacity: root.enabled ? 1.0 : 0.4

    LogosIcon {
        anchors.centerIn: parent
        width: 14
        height: 14
        source: root.iconSource
        // Light grey by default; hover lifts to the accent, matching InfoButton.
        color: hover.hovered ? Theme.palette.primary : Theme.palette.text
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.enabled
        onTapped: root.clicked()
    }
}
