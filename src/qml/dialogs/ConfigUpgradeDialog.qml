pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Icons
import Logos.Theme
import Logos.Controls
import Logos.BlockchainBackend 1.0

// The refused-config conversation: one dialog with two faces, chosen by
// `configState` alone.
//
//   ConfigStale       the node refused a config older than this release. The
//                     node upgrades a config from the previous release by
//                     itself when it starts, so this one is older than that
//                     and nothing here can rebuild it. Offer a fresh start.
//   ConfigUnreadable  the file is not a usable config at all. Nothing to offer.
//
// Every other configState leaves it hidden.
LogosWarningDialog {
    id: root

    // One of BlockchainBackend.ConfigState.
    required property int configState

    // Whether a keystore sits beside the config. It stays where it is either
    // way; the wording says so, because a fresh start means new keys.
    property bool hasKeystore: false

    // The node's own words for why it refused the config
    property string refusalReason: ""

    signal startFreshRequested()

    function rearm(): void { d.dismissed = false }
    function dismiss(): void { d.dismissed = true }

    QtObject {
        id: d

        property bool dismissed: false

        readonly property Item hostOverlay: root.Overlay.overlay

        readonly property bool stale: root.configState === BlockchainBackend.ConfigStale
        readonly property bool unreadable: root.configState === BlockchainBackend.ConfigUnreadable

        readonly property bool shouldShow: d.stale || d.unreadable
        readonly property real maxHeight: d.hostOverlay
            ? d.hostOverlay.height - 2 * Theme.spacing.xxlarge
            : 600

        readonly property string heading:
              d.unreadable ? qsTr("This config can't be read")
                           : qsTr("This config can't be updated")

        readonly property string body:
              d.unreadable ? root.refusalReason
            : qsTr("It was written for a release older than the one this version "
                   + "upgrades from, so the node won't start with it. Starting fresh "
                   + "creates a new node in its own folder, with a new keystore — a "
                   + "new wallet, and a new set of keys.")
              + (root.hasKeystore
                     ? " " + qsTr("The keystore beside this config is left where it is.")
                     : "")

        readonly property color accent:
              d.unreadable ? Theme.palette.error
                           : Theme.palette.primary

        readonly property url icon:
              d.unreadable ? LogosIcons.warning
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
    }

    leftActions: [
        LogosButton {
            objectName: "configUpgradeDismissButton"
            text: qsTr("Not now")
            onClicked: d.dismissed = true
        }
    ]

    rightActions: [
        LogosButton {
            objectName: "configStartFreshButton"
            variant: LogosButton.Variant.Primary
            visible: d.stale
            text: qsTr("Start fresh")
            onClicked: root.startFreshRequested()
        }
    ]
}
