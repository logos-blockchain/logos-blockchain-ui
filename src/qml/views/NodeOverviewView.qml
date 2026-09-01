import QtQuick
import QtQml
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

import "../controls"

// The design's first panel: node identity over the selected account's balance,
// with a Manage shortcut into the accounts view.
//
// The design's balance chart is deliberately left out — there is no historical
// balance API, so it would have nothing behind it.
Control {
    id: root

    // --- Public API ---
    required property var accountsModel

    // Address currently shown. Empty falls back to the model's first row.
    property string selectedAddress: ""
    property string balance: ""

    signal manageRequested()
    signal addressSelected(string addressHex)
    signal refreshRequested()

    property QtObject d: QtObject {
        id: d

        property int index: 0

        // Instantiator.count is reactive; the model's own rowCount() is a plain
        // method call with no NOTIFY, so a binding on it never re-evaluates as
        // rows arrive over QtRO and the panel stays stuck on "No account".
        readonly property int count: accounts.count

        function rowAt(i) {
            return (i >= 0 && i < count) ? accounts.objectAt(i) : null
        }

        function addressAt(i) {
            const r = rowAt(i)
            return r ? r.address : ""
        }

        function balanceAt(i) {
            const r = rowAt(i)
            return r ? r.balance : ""
        }

        function step(delta) {
            if (count === 0) return
            index = (index + delta + count) % count
            root.addressSelected(addressAt(index))
        }

        // Model for the dropdown: one elided label per account.
        readonly property var labels: {
            const out = []
            for (let i = 0; i < count; i++) out.push(elide(addressAt(i)))
            return out
        }

        function elide(a) {
            if (!a || a.length === 0) return qsTr("No account")
            return a.length > 24 ? a.slice(0, 10) + "......" + a.slice(-10) : a
        }
    }

    Instantiator {
        id: accounts
        model: root.accountsModel
        delegate: QtObject {
            required property string address
            required property string balance
        }
        onCountChanged: if (d.index >= count) d.index = 0
    }

    background: Rectangle {
        color: Theme.palette.background
    }

    contentItem: LogosFrame {
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusXlarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.large

            // ---- Identity ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Theme.spacing.tiny

                LogosText {
                    text: qsTr("Logos Blockchain")
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightRegular
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: qsTr("Node.")
                        color: Theme.palette.primary
                        // Design: Public Sans 700 40px/47 — off the type scale.
                        font.pixelSize: 40
                        font.weight: Theme.typography.weightBold
                    }

                    LogosBadge {
                        // Centred on "Node." rather than filling the 40px line
                        // box, which stretched it into a slab.
                        Layout.alignment: Qt.AlignVCenter
                        text: qsTr("ALPHA")
                        radius: Theme.spacing.radiusPill
                        color: Theme.palette.primary
                        // Design draws an outline, not a tint: LogosBadge's
                        // default backgroundColor is `color` at 18% alpha.
                        backgroundColor: "transparent"
                        // Thinner than the default `tiny` (4) top and bottom.
                        // The label keeps LogosBadge's own 11px/0.22-tracking —
                        // the type scale's secondaryText is 12 and reads heavy.
                        verticalPadding: 1
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            // ---- Selected account ----
            LogosFrame {
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: Theme.spacing.large
                backgroundColor: Theme.palette.backgroundInset
                borderColor: "transparent"
                radius: Theme.spacing.radiusLarge

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small

                        LogosText {
                            text: qsTr("Account")
                            color: Theme.palette.text
                            font.pixelSize: Theme.typography.subtitleText
                            font.weight: Theme.typography.weightMedium
                        }

                        Item { Layout.fillWidth: true }

                        // Switching here re-points the balance below, since both
                        // read the same row of the accounts model.
                        LogosComboBox {
                            id: accountPicker
                            Layout.preferredWidth: 260
                            enabled: d.count > 0
                            model: d.labels
                            currentIndex: d.index
                            placeholderText: qsTr("No account")
                            onActivated: (i) => {
                                d.index = i
                                root.addressSelected(d.addressAt(i))
                            }
                        }

                        StepperButton {
                            enabled: d.count > 1
                            iconSource: LogosIcons.arrowLeft
                            onClicked: d.step(-1)
                        }
                        StepperButton {
                            enabled: d.count > 1
                            iconSource: LogosIcons.arrowRight
                            onClicked: d.step(1)
                        }

                        // Balances are only fetched once, ~500ms after the node
                        // starts, so this is the way to pull a fresh number
                        // without leaving for the accounts view.
                        LogosIconButton {
                            flat: true
                            size: 28
                            iconSize: 16
                            iconSource: LogosIcons.refresh
                            iconColor: Theme.palette.textTertiary
                            onClicked: root.refreshRequested()
                        }

                        LogosIcon {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            source: Qt.resolvedUrl("../icons/accounts.svg")
                            color: Theme.palette.primary
                        }
                    }

                    LogosText {
                        text: qsTr("Token Balance")
                        color: Theme.palette.textTertiary
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                    }

                    LogosText {
                        Layout.fillWidth: true
                        text: {
                            if (root.balance && root.balance.length > 0) return root.balance
                            const b = d.balanceAt(d.index)
                            return b && b.length > 0 ? b : qsTr("—")
                        }
                        color: Theme.palette.text
                        // Design: DM Sans 400 38px/49 — matches the stats tiles.
                        font.pixelSize: 38
                        font.weight: Theme.typography.weightRegular
                        elide: Text.ElideRight
                    }

                }
            }

            // ---- Accounts shortcut ----
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Theme.spacing.medium

                LogosText {
                    text: qsTr("Accounts")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosButton {
                    text: qsTr("Manage")
                    onClicked: root.manageRequested()
                }
            }
        }
    }
}
