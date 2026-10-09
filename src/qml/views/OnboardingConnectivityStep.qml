import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "infoContent.js" as InfoContent

// Step 3: how other nodes reach this one. Only Blend core needs any of it, so
// it's optional and blank keeps the node's defaults.
ColumnLayout {
    id: root

    property string errorMessage: ""
    property bool locked: false
    property string userConfigPath: ""

    readonly property bool badBlendPort: blendPortField.text.length > 0
                                         && !blendPortField.textInput.acceptableInput
    readonly property bool valid: !root.badBlendPort
    // 0 leaves the node's default (3400).
    readonly property int blendPort: blendPortField.textInput.acceptableInput
                                     ? Number(blendPortField.text) : 0

    function reset() {
        blendPortField.text = ""
    }

    Component.onCompleted: root.reset()

    spacing: Theme.spacing.medium

    LogosText {
        text: qsTr("Connectivity")
        color: Theme.palette.text
        font.pixelSize: OnboardingText.stepHeading
        font.weight: Theme.typography.weightBold
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
        text: qsTr("How other nodes reach you. Only needed to join Blend as a core node: "
                   + "if you're not sure, leave it empty.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosNotice {
        objectName: "connectivityLockedNotice"
        Layout.fillWidth: true
        shown: root.locked
        severity: LogosNotice.Info
        title: qsTr("These settings are already written")
        message: root.userConfigPath.length > 0
            ? qsTr("Your node config exists, and it cannot be generated a second time, so "
                   + "nothing typed here would reach it. To change the Blend port, edit the "
                   + "file directly:\n\n%1").arg(root.userConfigPath)
            : qsTr("Your node config exists, and it cannot be generated a second time, so "
                   + "nothing typed here would reach it. Settings shows you where the file is.")
    }

    // ---- Blend port ----------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spacing.small
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Blend port")
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightMedium
        }

        Item { Layout.fillWidth: true }

        LogosInfoButton {
            title: qsTr("Blend port")
            dialogContentItem: InfoSections { info: InfoContent.blendPort }
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: -Theme.spacing.small
        text: qsTr("The UDP port other Blend nodes dial. Leave it empty for 3400.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosTextField {
        id: blendPortField
        objectName: "networkBlendPortField"
        Layout.preferredWidth: 160
        readOnly: root.locked
        placeholderText: "3400"
        validator: IntValidator { bottom: 1; top: 65535 }
    }

    LogosText {
        Layout.fillWidth: true
        visible: root.badBlendPort
        text: qsTr("Enter a port from 1 to 65535, or leave it empty for 3400.")
        color: Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosNotice {
        objectName: "networkErrorNotice"
        Layout.fillWidth: true
        shown: root.errorMessage.length > 0
        severity: LogosNotice.Error
        title: qsTr("Could not generate a config")
        message: root.errorMessage
        actions: [
            LogosCopyButton { value: root.errorMessage }
        ]
    }

    Item { Layout.fillHeight: true }

    // Generic to the step that writes the config, so it sits by the button.
    LogosText {
        Layout.fillWidth: true
        visible: !root.locked
        text: qsTr("Generating writes your config. After this step, these settings can "
                   + "only be changed by editing the file by hand.")
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }
}
