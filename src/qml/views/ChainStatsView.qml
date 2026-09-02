import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Chain statistics row from the design: three value tiles (At Headslot, Height,
// Slot) beside a card of chain identifiers (TiP, LiB, Peer ID).
//
// Fed by get_cryptarchia_info plus the peer id the view already resolves.
Control {
    id: root

    // --- Public API ---
    property string infoJson: ""
    // get_time_info payload; its current_slot is the consensus clock.
    property string timeInfoJson: ""
    property string peerId: ""

    signal copyToClipboard(string text)

    property QtObject d: QtObject {
        id: d

        readonly property var info: root.parse(root.infoJson)
        readonly property var timeInfo: root.parse(root.timeInfoJson)

        // How far the chain tip sits from the consensus clock, in slots.
        // Negative means behind; ~0 to a few slots back is healthy, since not
        // every slot produces a block. Undefined until both payloads arrive.
        readonly property var headslotDelta: {
            const tipSlot = root.field("slot")
            const currentSlot = timeInfo ? timeInfo.current_slot : undefined
            if (tipSlot === undefined || tipSlot === null) return undefined
            if (currentSlot === undefined || currentSlot === null) return undefined
            return Number(tipSlot) - Number(currentSlot)
        }

        // Floors low enough that the row keeps compressing with the window
        // rather than clipping: values elide, so shrinking degrades gracefully.
        // The identifiers card stays wider, since a hash needs room to be useful.
        readonly property int tileMinWidth: 110
        readonly property int hashLabelWidth: 90
    }

    // Same shape-tolerance as CryptarchiaInfoView: the payload arrives either
    // nested under "cryptarchia_info" or flat.
    function parse(s) {
        try { return s && s.length > 0 ? JSON.parse(s) : null } catch (e) { return null }
    }

    function field(key) {
        if (!d.info) return undefined
        if (d.info.cryptarchia_info && d.info.cryptarchia_info[key] !== undefined)
            return d.info.cryptarchia_info[key]
        return d.info[key]
    }

    function num(key) {
        var v = field(key)
        return (v === undefined || v === null) ? qsTr("—") : String(v)
    }

    function hash(key) {
        var v = field(key)
        return (v === undefined || v === null) ? "" : String(v)
    }

    background: Rectangle {
        color: Theme.palette.background
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacing.large

        StatTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: d.tileMinWidth
            label: qsTr("At Headslot")
            value: d.headslotDelta === undefined ? qsTr("—") : String(d.headslotDelta)
            info: qsTr("How many slots the chain tip sits from the consensus clock. Negative means behind. A few slots back is normal — not every slot produces a block. A large, growing gap means the node is falling behind.")
        }

        StatTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: d.tileMinWidth
            label: qsTr("Height")
            value: root.num("height")
            info: qsTr("Number of blocks in the chain up to the current tip.")
        }

        StatTile {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: d.tileMinWidth
            label: qsTr("Slot")
            value: root.num("slot")
            info: qsTr("Consensus slot of the current tip.")
        }

        // Chain identifiers.
        LogosFrame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 220
            padding: Theme.spacing.large
            backgroundColor: Theme.palette.surfaceRaised
            borderColor: "transparent"
            radius: Theme.spacing.radiusXlarge

            contentItem: ColumnLayout {
                spacing: Theme.spacing.medium

                // Design: label DM Sans 500 24px/31 #969696, value 11px #D1D1D1.
                HashRow {
                    label: qsTr("TiP")
                    labelWidth: d.hashLabelWidth
                    labelPixelSize: Theme.typography.panelTitleText
                    labelColor: Theme.palette.textTertiary
                    labelWeight: Theme.typography.weightMedium
                    value: root.hash("tip")
                    onCopyRequested: (t) => root.copyToClipboard(t)
                }

                // lib_slot rides along with the hash it belongs to rather than
                // getting its own tile: both describe the last irreversible
                // block, and the design has no fourth tile for it.
                HashRow {
                    label: qsTr("LiB")
                    labelWidth: d.hashLabelWidth
                    labelPixelSize: Theme.typography.panelTitleText
                    labelColor: Theme.palette.textTertiary
                    labelWeight: Theme.typography.weightMedium
                    note: root.field("lib_slot") !== undefined
                          ? qsTr("slot %1").arg(root.num("lib_slot"))
                          : ""
                    value: root.hash("lib")
                    onCopyRequested: (t) => root.copyToClipboard(t)
                }

                Item { Layout.fillHeight: true }

                // Peer ID sits smaller in the design, with a mono label.
                HashRow {
                    label: qsTr("Peer ID:")
                    labelWidth: d.hashLabelWidth
                    labelColor: Theme.palette.textTertiary
                    value: root.peerId
                    onCopyRequested: (t) => root.copyToClipboard(t)
                }
            }
        }
    }
}
