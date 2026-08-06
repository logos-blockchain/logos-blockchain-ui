import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Rectangle {
    id: root

    // --- Public API ---
    required property string statusText
    required property color  statusColor
    property string statusDetail: ""
    required property string userConfig
    required property string deploymentConfig
    required property bool   useGeneratedConfig
    // Offer Start only when the backend confirms the node is down; offer Stop
    // when it's up or in the ambiguous Error state. Both false during the
    // transient Starting/Stopping states (button disabled).
    required property bool   canStart
    required property bool   canStop
    // True while the status monitor is paused after repeated failed status
    // calls — surfaces a Resume button. The node itself is unaffected.
    property bool            monitoringPaused: false

    signal startRequested()
    signal stopRequested()
    signal resumeMonitoringRequested()
    signal changeConfigRequested()

    implicitHeight: contentLayout.height + Theme.spacing.large
    color: Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.color: Theme.palette.border
    border.width: 1

    RowLayout {
        id: contentLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacing.large
        spacing: Theme.spacing.large

        // Status Card
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                LogosText {
                    Layout.fillWidth: true
                    font.bold: true
                    text: root.statusText
                    elide: Text.ElideRight
                    color: root.statusColor
                }
                LogosText {
                    Layout.fillWidth: true
                    text: root.statusDetail || qsTr("Mainnet - chain ID 1")
                    font.pixelSize: Theme.typography.secondaryText
                    color: root.statusDetail ? root.statusColor : Theme.palette.textSecondary
                    elide: Text.ElideRight
                }
            }
            // Resume the paused status monitor. Node is untouched — this only
            // restarts polling.
            LogosButton {
                visible: root.monitoringPaused
                Layout.preferredWidth: 150
                text: qsTr("Resume monitoring")
                onClicked: root.resumeMonitoringRequested()
            }

            LogosButton {
                // Width pinned so the label toggling Start/Stop doesn't jitter.
                Layout.preferredWidth: 100
                enabled: root.canStop || root.canStart
                text: root.canStop ? qsTr("Stop Node") : qsTr("Start Node")
                onClicked: root.canStop ? root.stopRequested() : root.startRequested()
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Theme.palette.borderSecondary
        }

        // Config Card
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosText {
                        text: qsTr("User Config: ")
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: (root.userConfig || qsTr("No file selected")) +
                              (root.useGeneratedConfig ? " " + qsTr("(Generated)") : "")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        // A long absolute config path has no spaces to wrap on and
                        // overflows the row — elide the middle so the leading dirs
                        // and the file name both stay visible.
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosText {
                        text: qsTr("Deployment Config: ")
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: (root.useGeneratedConfig && root.deploymentConfig ?
                                   root.deploymentConfig :
                                   root.useGeneratedConfig ?
                                       qsTr("Default") :
                                       (root.deploymentConfig || qsTr("No file selected")))
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        elide: Text.ElideMiddle
                    }
                }
            }

            LogosButton {
                // Config can't be changed while the node may be up — hide the
                // button entirely (not just disable it) in Running/Error.
                visible: !root.canStop
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 100
                Layout.preferredHeight: 40
                text: qsTr("Change")
                onClicked: root.changeConfigRequested()
            }
        }
    }
}
