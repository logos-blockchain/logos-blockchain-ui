pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Joining Blend as a core node, and watching it afterwards
LogosDialog {
    id: root

    // Everything shown; the host owns it and its values.
    property BlendCoreState blend

    signal refreshRequested()
    signal joinRequested(string locator)
    signal leaveRequested()

    function show(): void {
        root.blend.page = "gates"
        root.blend.attested = false
        root.blend.confirmingLeave = false
        joinPages.collapse()
        root.open()
    }

    QtObject {
        id: d

        // Asks the host to re-read every 5 s while open and the node runs.
        property Timer refresh: Timer {
            interval: 5000
            repeat: true
            triggeredOnStart: true
            running: root.visible && !!root.blend && root.blend.nodeRunning
            onTriggered: root.refreshRequested()
        }
    }

    title: root.blend.heading
    backgroundColor: Theme.palette.surface
    parent: Overlay.overlay
    anchors.centerIn: parent
    closePolicy: root.blend.busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    width: parent ? Math.min(520, parent.width - 2 * Theme.spacing.xxlarge) : 520
    height: parent ? Math.min(implicitHeight, parent.height - 2 * Theme.spacing.xxlarge)
                   : implicitHeight

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium

        LogosText {
            Layout.fillWidth: true
            text: qsTr("Become a Blend Network core provider: mix traffic for the "
                       + "network and earn a share of its rewards.")
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        LogosScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: body.implicitHeight
            contentWidth: availableWidth

            ColumnLayout {
                id: body
                width: scroll.availableWidth
                spacing: Theme.spacing.small

                BlendJoinPages { id: joinPages; blend: root.blend }
                BlendStatusPages { blend: root.blend }

                LogosNotice {
                    objectName: "blendActionError"
                    Layout.fillWidth: true
                    shown: root.blend.actionError.length > 0 && !root.blend.busy
                    severity: LogosNotice.Error
                    title: root.blend.declared ? qsTr("Couldn't leave") : qsTr("Couldn't join")
                    message: root.blend.actionError
                }
            }
        }
    }

    leftActions: [
        LogosText {
            width: Math.min(implicitWidth, 200)
            wrapMode: Text.WordWrap
            visible: !root.blend.busy && !root.blend.declared && root.blend.page === "gates"
            text: root.blend.allMet ? qsTr("All checks passed — ready to enable.")
                           : qsTr("Resolve the red checks above to enable.")
            color: root.blend.allMet ? Theme.palette.success : Theme.palette.textTertiary
            font.pixelSize: 11
        }
    ]

    rightActions: [
        LogosButton {
            objectName: "blendCancelButton"
            visible: !root.blend.declared && root.blend.page === "gates"
            enabled: !root.blend.busy
            text: qsTr("Cancel")
            onClicked: root.close()
        },
        LogosButton {
            objectName: "blendBackButton"
            visible: !root.blend.declared && root.blend.page === "confirm"
            enabled: !root.blend.busy
            text: qsTr("Back")
            onClicked: root.blend.page = "gates"
        },
        LogosButton {
            objectName: "blendContinueButton"
            visible: !root.blend.declared && root.blend.page === "gates"
            variant: LogosButton.Variant.Primary
            enabled: root.blend.allMet
            text: qsTr("Enable Blend Core")
            onClicked: root.blend.page = "confirm"
        },
        LogosButton {
            objectName: "blendJoinButton"
            visible: !root.blend.declared && root.blend.page === "confirm"
            variant: LogosButton.Variant.Primary
            enabled: !root.blend.busy && root.blend.allMet
            text: root.blend.busy ? qsTr("Submitting…") : qsTr("Confirm and enable")
            onClicked: root.joinRequested(root.blend.locator)
        },
        LogosButton {
            id: leaveButton
            objectName: "blendLeaveButton"
            visible: root.blend.canLeave && !root.blend.confirmingLeave
            enabled: root.blend.apiAvailable && !root.blend.busy
            text: qsTr("Disable Blend Core")
            onClicked: root.blend.confirmingLeave = true
            LogosToolTip {
                text: qsTr("Leaving isn't available on this node yet")
                visible: leaveButton.hovered && !root.blend.apiAvailable
            }
        },
        LogosButton {
            objectName: "blendLeaveBackButton"
            visible: root.blend.confirmingLeave && !root.blend.withdrawn
            enabled: !root.blend.busy
            text: qsTr("Back")
            onClicked: root.blend.confirmingLeave = false
        },
        LogosButton {
            objectName: "blendLeaveConfirmButton"
            visible: root.blend.confirmingLeave && !root.blend.withdrawn
            variant: LogosButton.Variant.Primary
            enabled: !root.blend.busy
            text: root.blend.busy ? qsTr("Submitting…") : qsTr("Withdraw")
            onClicked: root.leaveRequested()
        },
        LogosButton {
            objectName: "blendDoneButton"
            visible: root.blend.declared && !root.blend.confirmingLeave
            text: qsTr("Close")
            onClicked: root.close()
        }
    ]
}
