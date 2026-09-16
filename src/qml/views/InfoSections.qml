import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

import Logos.Theme
import Logos.Controls

QQC.ScrollView {
    id: root

    property var info: null
    property real maxHeight: 360

    // Exposed for tests.
    readonly property alias docsLinkItem: docsLink
    readonly property alias docsCopyItem: docsCopy

    clip: true
    contentWidth: availableWidth
    QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
    QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded
    implicitHeight: Math.min(sections.implicitHeight, root.maxHeight)

    component Section: ColumnLayout {
        id: sec

        property string heading: ""
        property string text: ""

        Layout.fillWidth: true
        spacing: Theme.spacing.tiny
        visible: sec.text.length > 0

        LogosText {
            text: sec.heading
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightBold
        }

        LogosText {
            Layout.fillWidth: true
            text: sec.text
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        id: sections
        width: root.availableWidth
        spacing: Theme.spacing.medium

        Section {
            heading: qsTr("WHAT IS IT")
            text: (root.info && root.info.what) ? root.info.what : ""
        }

        Section {
            heading: qsTr("HOW IT'S CALCULATED")
            text: (root.info && root.info.calc) ? root.info.calc : ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.tiny
            visible: !!(root.info && root.info.states && root.info.states.length > 0)

            LogosText {
                text: qsTr("STATES")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
                font.weight: Theme.typography.weightBold
            }

            Repeater {
                model: (root.info && root.info.states) ? root.info.states : []

                RowLayout {
                    id: stateRow

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        Layout.preferredWidth: 110
                        Layout.alignment: Qt.AlignTop
                        text: stateRow.modelData.label
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                        wrapMode: Text.WordWrap
                    }

                    LogosText {
                        Layout.fillWidth: true
                        text: stateRow.modelData.meaning
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.tiny
            visible: !!(root.info && root.info.docs && root.info.docs.length > 0)

            LogosText {
                text: qsTr("DOCS")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
                font.weight: Theme.typography.weightBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosLink {
                    id: docsLink
                    Layout.fillWidth: true
                    text: (root.info && root.info.docs) ? root.info.docs : ""
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideRight
                    onActivated: docsCopy.copy()
                }

                LogosCopyButton {
                    id: docsCopy
                    Layout.alignment: Qt.AlignVCenter
                    value: (root.info && root.info.docs) ? root.info.docs : ""
                }
            }
        }
    }
}
