import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

Item {
    id: root

    property bool busy: false
    property string busyMessage: ""
    property string errorMessage: ""

    property bool canExit: false
    // No bootstrap peers configured means no Quick start
    property bool quickStartAvailable: true

    signal quickStartRequested()
    signal advancedRequested()
    signal exitRequested()

    Image {
        id: backdrop
        anchors.fill: parent
        source: LogosIcons.onboardingBackdrop
        fillMode: Image.PreserveAspectCrop
        mipmap: true
    }
    property real backdropTint: 0.42

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.backdropTint)
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 360)
        spacing: Theme.spacing.medium
        visible: !root.busy

        LogosText {
            Layout.fillWidth: true
            text: qsTr("Blockchain Node")
            color: Theme.palette.text
            font.pixelSize: Theme.typography.pageTitleText
            font.weight: Theme.typography.weightBold
            horizontalAlignment: Text.AlignHCenter
        }

        LogosButton {
            objectName: "quickStartButton"
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            variant: LogosButton.Variant.Primary
            visible: root.quickStartAvailable
            font.pixelSize: Theme.typography.primaryText
            font.weight: Theme.typography.weightMedium
            enabled: !root.busy
            text: root.busy
                  ? (root.busyMessage.length > 0 ? root.busyMessage : qsTr("Working…"))
                  : qsTr("Quick start")
            onClicked: root.quickStartRequested()
        }

        LogosButton {
            objectName: "advancedSetupButton"
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            font.pixelSize: Theme.typography.primaryText
            font.weight: Theme.typography.weightMedium
            enabled: !root.busy
            text: root.quickStartAvailable ? qsTr("Advanced") : qsTr("Set up your node")
            onClicked: root.advancedRequested()

            background: Rectangle {
                readonly property var control: parent

                radius: control.radius
                color: !control.enabled ? Theme.palette.backgroundMuted
                     : control.pressed  ? Theme.palette.background
                     : control.hovered  ? Theme.palette.backgroundTertiary
                                        : Theme.palette.backgroundSecondary
                border.width: 1
                border.color: control.isActive ? Theme.palette.overlayOrange
                                               : Theme.palette.border
            }
        }

    }

    Rectangle {
        anchors.fill: parent
        visible: root.busy
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true

            onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacing.medium

            LogosSpinner {
                Layout.alignment: Qt.AlignHCenter
                running: root.busy
            }

            LogosText {
                Layout.alignment: Qt.AlignHCenter
                text: root.busyMessage.length > 0 ? root.busyMessage : qsTr("Working…")
                color: Theme.palette.text
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
            }

            LogosText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Writing your config, creating your keys, and starting the node.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    LogosNotice {
        objectName: "welcomeErrorNotice"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        shown: root.errorMessage.length > 0
        severity: LogosNotice.Error
        title: qsTr("Could not generate a config")
        message: root.errorMessage
        actions: [
            LogosCopyButton { value: root.errorMessage }
        ]
    }
}
