import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Left-hand section nav: an icon and a label per entry, one selected at a time.
LogosListView {
    id: root

    // --- Public API ---
    property var sections: []
    property bool nodeRunning: false
    property url iconDir: Qt.resolvedUrl("../icons/")
    property int iconSize: 18
    readonly property bool hasIcons: sections.some(function(s) {
        return s && s.icon && s.icon.length > 0
    })

    signal sectionActivated(int index)

    Layout.preferredWidth: 200
    Layout.minimumWidth: 160
    Layout.maximumWidth: 200
    Layout.fillHeight: true

    model: root.sections

    delegate: LogosItemDelegate {
        id: cell

        required property int index
        required property var modelData

        width: ListView.view.width
        topPadding: 0
        bottomPadding: 0
        text: cell.modelData.label
        enabled: !cell.modelData.needsNode || root.nodeRunning
        highlighted: ListView.isCurrentItem
        radius: Theme.spacing.radiusLarge
        highlightColor: Theme.palette.surfaceRaised
        hoverColor: Theme.colors.getColor(Theme.palette.text, 0.05)
        textColor: (cell.highlighted || cell.hovered)
                       ? Theme.palette.text
                       : Theme.palette.textSecondary
        onClicked: root.sectionActivated(cell.index)

        contentItem: RowLayout {
            spacing: Theme.spacing.small

            LogosIcon {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.iconSize
                Layout.preferredHeight: root.iconSize
                visible: root.hasIcons
                source: (cell.modelData.icon || "").length > 0
                            ? root.iconDir + cell.modelData.icon
                            : ""
                color: !cell.enabled ? Theme.palette.textMuted
                     : cell.highlighted ? Theme.palette.primary
                     : cell.textColor
            }

            LogosText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: cell.text
                font.pixelSize: Theme.typography.secondaryText
                font.weight: cell.highlighted ? Theme.typography.weightBold
                                              : Theme.typography.weightRegular
                verticalAlignment: Text.AlignVCenter
                color: cell.enabled ? cell.textColor : Theme.palette.textMuted
                elide: Text.ElideRight
            }
        }
    }
}
