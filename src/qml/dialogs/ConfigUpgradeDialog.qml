pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Icons
import Logos.Theme
import Logos.Controls
import Logos.BlockchainBackend 1.0

// The config-upgrade conversation: one dialog with three faces, chosen by
// `configState` alone.
//
//   ConfigStale       the node refused a config older than this release.
//                     With a keystore: offer to rebuild it. Without one:
//                     explain that only a fresh start is possible.
//   ConfigUnreadable  the file is not a usable config at all. Nothing to offer.
//   ConfigUpgraded    a rebuild happened. Report what it could not carry over
//                     and where the backup went.
//
// Every other configState leaves it hidden.x
LogosWarningDialog {
    id: root

    // One of BlockchainBackend.ConfigState.
    required property int configState

    // Settings this release no longer recognises, dotted as the node names them
    // ("blend.core.backend.core_peering_degree"). Rendered only while Upgraded.
    property var configDropped: []

    // Where the pre-upgrade config was saved
    property string configBackupPath: ""

    // Whether a keystore sits beside the config
    property bool hasKeystore: false

    // The node's own words for why it refused the config
    property string refusalReason: ""

    // An upgrade is in flight. Disables every action and shows a spinner.
    property bool busy: false

    signal upgradeRequested()
    signal startNodeRequested()
    signal startFreshRequested()

    function rearm(): void { d.dismissed = false }

    QtObject {
        id: d

        property bool dismissed: false

        readonly property Item hostOverlay: root.Overlay.overlay

        readonly property bool stale: root.configState === BlockchainBackend.ConfigStale
        readonly property bool upgraded: root.configState === BlockchainBackend.ConfigUpgraded
        readonly property bool unreadable: root.configState === BlockchainBackend.ConfigUnreadable
        readonly property bool canUpgrade: d.stale && root.hasKeystore
        readonly property bool hasDropped: root.configDropped.length > 0

        readonly property bool shouldShow: d.stale || d.upgraded || d.unreadable
        readonly property real maxHeight: d.hostOverlay
            ? d.hostOverlay.height - 2 * Theme.spacing.xxlarge
            : 600

        readonly property string heading:
              d.upgraded   ? qsTr("Config updated")
            : d.unreadable ? qsTr("This config can't be read")
            : d.canUpgrade ? qsTr("Your config is out of date")
                           : qsTr("This config can't be updated")

        readonly property string body:
              d.upgraded   ? (d.hasDropped
                                ? qsTr("Your settings and keys were carried over. These couldn't "
                                       + "be — they no longer exist in this release:")
                                : qsTr("Your settings and keys were carried over."))
            : d.unreadable ? root.refusalReason
            : d.canUpgrade ? qsTr("It was written for an older release, so the node won't start "
                                  + "with it. Updating rebuilds it against this release and keeps "
                                  + "your settings and your keys.")
                           : qsTr("No keystore was found next to it, so a replacement can't be "
                                  + "built from your keys. Starting fresh will create a new "
                                  + "keystore — a new wallet, and a new set of keys.")

        readonly property color accent:
              d.upgraded   ? Theme.palette.success
            : d.unreadable ? Theme.palette.error
                           : Theme.palette.primary

        readonly property url icon:
              d.upgraded   ? LogosIcons.check
            : d.unreadable ? LogosIcons.warning
                           : LogosIcons.info
    }

    onConfigStateChanged: d.dismissed = false

    parent: d.hostOverlay
    anchors.centerIn: parent

    visible: d.shouldShow && !d.dismissed
    modal: true
    closePolicy: Popup.NoAutoClose

    width: d.hostOverlay
           ? Math.min(560, d.hostOverlay.width - 2 * Theme.spacing.xxlarge)
           : 560
    height: Math.min(implicitHeight, d.maxHeight)

    title: d.heading
    accentColor: d.accent
    iconSource: d.icon

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium

        LogosText {
            Layout.fillWidth: true
            Layout.fillHeight: false
            text: d.body
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(contentHeight, 160)
            visible: d.upgraded && d.hasDropped
            clip: true
            model: root.configDropped
            ScrollBar.vertical: LogosScrollBar { policy: ScrollBar.AsNeeded }

            delegate: LogosText {
                required property string modelData

                width: ListView.view.width
                text: modelData
                elide: Text.ElideMiddle
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
                font.family: Theme.typography.mono
            }
        }

        LogosText {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: d.upgraded
            text: qsTr("Comments and formatting from the original aren't carried over.")
            wrapMode: Text.WordWrap
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: d.upgraded && root.configBackupPath.length > 0
            spacing: Theme.spacing.tiny

            LogosText {
                text: qsTr("Previous config saved at")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }
            LogosText {
                Layout.fillWidth: true
                text: root.configBackupPath
                elide: Text.ElideMiddle
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
                font.family: Theme.typography.mono
            }
            LogosCopyButton {
                Layout.preferredHeight: 24
                Layout.preferredWidth: 24
                value: root.configBackupPath
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.busy
            spacing: Theme.spacing.small

            LogosSpinner { running: root.busy }
            LogosText {
                text: qsTr("Updating…")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }

    leftActions: [
        LogosButton {
            objectName: "configUpgradeDismissButton"
            visible: !d.upgraded
            enabled: !root.busy
            text: qsTr("Not now")
            onClicked: d.dismissed = true
        }
    ]

    rightActions: [
        LogosButton {
            objectName: "configUpgradeButton"
            variant: LogosButton.Variant.Primary
            visible: d.canUpgrade
            enabled: !root.busy
            text: qsTr("Update config")
            onClicked: root.upgradeRequested()
        },
        LogosButton {
            objectName: "configStartFreshButton"
            visible: d.stale && !root.hasKeystore
            enabled: !root.busy
            text: qsTr("Start fresh")
            onClicked: root.startFreshRequested()
        },
        LogosButton {
            objectName: "configStartNodeButton"
            variant: LogosButton.Variant.Primary
            visible: d.upgraded
            enabled: !root.busy
            text: qsTr("Start node")
            onClicked: root.startNodeRequested()
        }
    ]
}
