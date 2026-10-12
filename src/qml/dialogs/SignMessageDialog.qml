pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Another app asks the node to sign (the node.sign_referral_* intents). Shows
// who asks, what for and every byte that gets signed; the host confirms with
// SignConfirmDialog and answers.
LogosDialog {
    id: root

    required property SignRequestState request

    signal signRequested()
    signal declineRequested()
    signal startNodeRequested()

    title: qsTr("Sign message")
    backgroundColor: Theme.palette.surface
    parent: Overlay.overlay
    anchors.centerIn: parent
    closePolicy: root.request.busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    width: parent ? Math.min(560, parent.width - 2 * Theme.spacing.xxlarge) : 560
    height: parent ? Math.min(implicitHeight, parent.height - 2 * Theme.spacing.xxlarge)
                   : implicitHeight

    onClosed: if (root.request.current !== null && !root.request.busy) root.declineRequested()

    QtObject {
        id: d

        // Wide enough for the longest label, so no value runs into its label.
        readonly property real labelWidth: {
            const labels = [qsTr("Requested by"), qsTr("Your node")]
            if (root.request.valid)
                for (const row of root.request.built.rows)
                    labels.push(row.label)
            return Math.ceil(Math.max(...labels.map(l => d.labelMetrics.advanceWidth(l))))
        }

        readonly property FontMetrics labelMetrics: FontMetrics {
            font.pixelSize: Theme.typography.secondaryText
            font.family: Theme.typography.publicSans
        }
    }

    component DetailRow: RowLayout {
        id: detailRow

        property string label: ""
        property string value: ""
        property bool mono: false

        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        LogosText {
            Layout.preferredWidth: d.labelWidth
            Layout.minimumWidth: d.labelWidth
            Layout.alignment: Qt.AlignTop
            text: detailRow.label
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            // A long key's unwrapped width would otherwise squeeze the label.
            Layout.preferredWidth: 1
            text: detailRow.value
            // Every character shows: nothing about what is signed may be elided.
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.family: detailRow.mono ? Theme.typography.mono : Theme.typography.publicSans
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium

        LogosText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.request.purpose
            wrapMode: Text.WordWrap
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightMedium
        }

        LogosNotice {
            objectName: "signWarning"
            Layout.fillWidth: true
            shown: root.request.valid
            severity: LogosNotice.Warning
            title: qsTr("You're signing with your node's key")
            message: qsTr("Only sign if you started this yourself in %1.").arg(root.request.requester)
        }

        LogosText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.request.summary
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
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

                DetailRow {
                    label: qsTr("Requested by")
                    value: root.request.requester
                }

                Repeater {
                    model: root.request.valid ? root.request.built.rows : []
                    delegate: DetailRow {
                        required property var modelData
                        label: modelData.label
                        value: modelData.value.length > 0 ? modelData.value : qsTr("No one (you start your own tree)")
                        mono: modelData.value.length > 0
                    }
                }

                DetailRow {
                    visible: root.request.valid
                    label: qsTr("Your node")
                    value: root.request.signingKey
                    mono: true
                }

                LogosText {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.small
                    visible: root.request.valid
                    text: qsTr("The signature can't be used as a transaction and can't move funds.")
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                }

                LogosFrame {
                    objectName: "signMessageBody"
                    Layout.fillWidth: true
                    visible: root.request.valid
                    backgroundColor: Theme.palette.surfaceRaised
                    borderColor: "transparent"
                    radius: Theme.spacing.radiusMedium

                    ColumnLayout {
                        objectName: "signMessageColumn"
                        anchors.fill: parent
                        spacing: Theme.spacing.small

                        LogosText {
                            text: qsTr("Exact message (%1)").arg(root.request.built.domain || "")
                            color: Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                        }
                        LogosText {
                            Layout.fillWidth: true
                            text: root.request.built.message || ""
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                            color: Theme.palette.text
                            font.pixelSize: Theme.typography.secondaryText
                            font.family: Theme.typography.mono
                        }
                    }
                }

                LogosNotice {
                    objectName: "signInvalid"
                    Layout.fillWidth: true
                    shown: root.request.current !== null && !root.request.valid
                    severity: LogosNotice.Error
                    title: qsTr("Can't sign this request")
                    message: root.request.problem
                }

                LogosNotice {
                    objectName: "signNodeStopped"
                    Layout.fillWidth: true
                    shown: root.request.valid && !root.request.nodeRunning
                    severity: LogosNotice.Warning
                    title: root.request.nodeStarting ? qsTr("Your node is starting")
                                                     : qsTr("Your node isn't running")
                    message: root.request.canStartNode
                             ? qsTr("Only a running node can sign. Start it, then sign.")
                             : qsTr("Only a running node can sign. Finish setting up your node first.")
                }

                LogosNotice {
                    objectName: "signError"
                    Layout.fillWidth: true
                    shown: root.request.actionError.length > 0 && !root.request.busy
                    severity: LogosNotice.Error
                    title: qsTr("Couldn't sign")
                    message: root.request.actionError
                }
            }
        }
    }

    leftActions: [
        LogosText {
            visible: root.request.waiting > 0
            text: qsTr("%n more request(s) after this one", "", root.request.waiting)
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }
    ]

    rightActions: [
        LogosButton {
            objectName: "signDeclineButton"
            enabled: !root.request.busy
            text: root.request.malformed ? qsTr("Close") : qsTr("Decline")
            onClicked: root.declineRequested()
        },
        LogosButton {
            objectName: "signStartNodeButton"
            visible: root.request.valid && !root.request.nodeRunning
            enabled: root.request.canStartNode && !root.request.nodeStarting
            text: root.request.nodeStarting ? qsTr("Starting…") : qsTr("Start node")
            onClicked: root.startNodeRequested()
        },
        LogosButton {
            objectName: "signApproveButton"
            visible: root.request.valid && root.request.nodeRunning
            variant: LogosButton.Variant.Primary
            enabled: root.request.canSign
            text: root.request.busy ? qsTr("Signing…") : qsTr("Sign")
            onClicked: root.signRequested()
        }
    ]
}
