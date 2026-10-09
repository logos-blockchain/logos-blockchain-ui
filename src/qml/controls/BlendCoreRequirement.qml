import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

// One requirement of the Blend Core dialog, as its own block. The one-line fix
// shows only while it isn't met. The longer why expands in place from the
// header line, like an explorer block row, since a LogosInfoButton would stack
// a second modal on the dialog. Extra items (inputs, a checkbox) go below.
LogosFrame {
    id: root

    property var ok: null
    property string label: ""
    property string value: ""
    property string fix: ""
    property string detail: ""
    property bool expanded: false
    property string copyValue: ""
    property string linkText: ""
    property string linkValue: ""
    default property alias extra: extraColumn.data
    // The details only open on a problem, where they say how to fix it.
    readonly property bool canExpand: root.ok === false && root.detail.length > 0

    Layout.fillWidth: true
    Layout.fillHeight: false
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: "transparent"
    radius: Theme.spacing.radiusMedium

    // Green disc with a knocked-out check, a red ringed "!", a spinner while
    // the check runs, or an empty ring when it can't run.
    component StatusDisc: Item {
        id: disc
        property var ok: null
        property color cutout: Theme.palette.surfaceRaised

        implicitWidth: 18
        implicitHeight: 18

        // Met: a filled disc with the check knocked out.
        Rectangle {
            anchors.fill: parent
            visible: disc.ok === true
            radius: width / 2
            color: Theme.palette.success
        }
        // Can't be checked right now (the node is stopped).
        Rectangle {
            anchors.fill: parent
            visible: disc.ok === "idle"
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.palette.textTertiary
        }
        // Still being checked.
        LogosSpinner {
            anchors.fill: parent
            visible: disc.ok === null || disc.ok === undefined
            running: visible
            ringColor: Theme.palette.textTertiary
            thickness: 2
            dotSize: 3
        }
        LogosIcon {
            anchors.centerIn: parent
            width: 12
            height: 12
            visible: disc.ok === true
            source: LogosIcons.check
            color: disc.cutout
        }
        // Not met: the warning glyph is already a ringed "!".
        LogosIcon {
            anchors.fill: parent
            visible: disc.ok === false
            source: LogosIcons.warning
            color: Theme.palette.error
            // The asset is near-black; lift it first or the tint stays dark.
            brightness: 1.0
        }
    }

    // A Frame sizes itself to its content but doesn't stretch it: fill it, or
    // the row shrinks to its implicit width and loses its right-aligned value.
    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacing.medium

        StatusDisc {
            Layout.alignment: Qt.AlignTop
            ok: root.ok
        }

        ColumnLayout {
            id: extraColumn
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Theme.spacing.small

                LogosText {
                    text: root.label
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }
                Item { Layout.fillWidth: true }
                LogosText {
                    Layout.maximumWidth: 260
                    visible: root.ok !== "idle"
                    text: root.value
                    elide: Text.ElideMiddle
                    color: root.ok === true ? Theme.palette.success : Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                }

                // Always holds its slot, so every row's value ends at the same edge.
                Image {
                    objectName: root.objectName + "Expand"
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 12
                    Layout.alignment: Qt.AlignVCenter
                    source: LogosIcons.triangleDown
                    sourceSize.width: 48
                    sourceSize.height: 24
                    fillMode: Image.PreserveAspectFit
                    opacity: root.canExpand ? 0.55 : 0
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 120 } }
                }
                TapHandler {
                    enabled: root.canExpand
                    onTapped: root.expanded = !root.expanded
                }
                HoverHandler {
                    enabled: root.canExpand
                    cursorShape: Qt.PointingHandCursor
                }
            }

            LogosText {
                Layout.fillWidth: true
                visible: root.ok === false && root.fix.length > 0
                text: root.fix
                wrapMode: Text.WordWrap
                color: Theme.palette.textTertiary
                font.pixelSize: 11
            }

            LogosText {
                Layout.fillWidth: true
                visible: root.canExpand && root.expanded && root.detail.length > 0
                text: root.detail
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                font.pixelSize: 11
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.canExpand && root.expanded && root.copyValue.length > 0
                spacing: Theme.spacing.small
                LogosText {
                    Layout.fillWidth: true
                    text: root.copyValue
                    elide: Text.ElideMiddle
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                    font.pixelSize: 11
                }
                LogosCopyButton { value: root.copyValue }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.ok === false && root.linkText.length > 0
                spacing: Theme.spacing.small
                LogosLink {
                    Layout.fillWidth: true
                    text: root.linkText
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    onActivated: linkCopy.copy()
                }
                LogosCopyButton { id: linkCopy; value: root.linkValue }
            }
        }
    }
}
