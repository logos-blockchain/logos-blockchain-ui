import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

// One row of the blocks table (BlockModel row), expandable in place.
//   Collapsed: timestamp · slot · consensus version · tx count
//   Expanded:  header hashes, proof-of-leadership group, transactions list
// Unparsed payloads fall back to showing their raw text.
//
// Column widths are supplied by BlocksView so cells line up with its header.
Rectangle {
    id: del

    signal copyToClipboard(string text)

    // Column geometry, set by BlocksView so the row lines up with its header.
    property int timestampWidth: 180
    property int consensusWidth: 200
    property int txsWidth: 180
    property int chevronWidth: 42
    property int rowPadding: 12

    QtObject {
        id: d

        // Expansion state.
        property bool expanded: false
        property bool proofExpanded: false

        // Design: Table Row Cell [1.0] is 64px tall.
        readonly property int summaryHeight: 64

        // The transactions role is a QStringList; surface it for the Repeater.
        readonly property var transactionsList: model.transactions || []

        // Roles read as `undefined` during the brief QtRO replica sync at node
        // startup. Treat the fallback as active ONLY when the model says so
        // explicitly (parsed === false); undefined means "still loading", not
        // "unparsed" — otherwise freshly-arrived blocks flash as Unparsed.
        readonly property bool isUnparsed: model.parsed === false
    }

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: col.implicitHeight

    // backgroundMuted is a 7% light overlay, so it lifts whatever surface the
    // card provides. (Not surfaceInteractiveHover: that token only exists in
    // logos-design-system's checkout, not in the revision this repo pins.)
    color: rowHover.hovered ? Theme.palette.backgroundMuted : "transparent"

    HoverHandler { id: rowHover }

    // Row separator
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.palette.borderTertiaryMuted
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // ---- Summary row (always visible, toggles expansion) ----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: d.summaryHeight

            TapHandler { onTapped: d.expanded = !d.expanded }

            // Cells sit flush (design has no inter-column gap); each insets its
            // own content by `rowPadding`, matching the header.
            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Timestamp — design: Paragraph/Small, Inter 400 14px/20, #FFFFFF.
                Item {
                    Layout.preferredWidth: del.timestampWidth
                    Layout.fillHeight: true

                    LogosText {
                        anchors.left: parent.left
                        anchors.leftMargin: del.rowPadding
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.timestamp || ""
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.primaryText
                        font.weight: Theme.typography.weightRegular
                        elide: Text.ElideRight
                    }
                }

                // Block — design: Label/Medium, Inter 700 16px/24, #FFFFFF.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    LogosText {
                        anchors.left: parent.left
                        anchors.leftMargin: del.rowPadding
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.isUnparsed
                              ? qsTr("Unparsed block")
                              : qsTr("Slot %1").arg(model.slot || qsTr("?"))
                        color: d.isUnparsed ? Theme.palette.warning : Theme.palette.text
                        font.pixelSize: Theme.typography.subtitleText
                        font.weight: Theme.typography.weightBold
                        elide: Text.ElideRight
                    }
                }

                // Consensus — the block header's `version` field (e.g. Bedrock).
                Item {
                    Layout.preferredWidth: del.consensusWidth
                    Layout.fillHeight: true

                    LogosBadge {
                        anchors.left: parent.left
                        anchors.leftMargin: del.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !d.isUnparsed && (model.version || "").length > 0
                        text: model.version || ""
                        radius: Theme.spacing.radiusMedium
                        backgroundColor: Theme.palette.backgroundButton
                        borderColor: Theme.palette.borderHairline
                        labelItem.color: Theme.palette.text
                        labelItem.font.pixelSize: Theme.typography.primaryText
                    }
                }

                // TXs — design: Label/Medium, Inter 700 16px/24. Blanked rather
                // than hidden: RowLayout collapses invisible items, which would
                // pull this row's chevron out of line with the rest.
                Item {
                    Layout.preferredWidth: del.txsWidth
                    Layout.fillHeight: true

                    LogosText {
                        anchors.left: parent.left
                        anchors.leftMargin: del.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.isUnparsed
                              ? ""
                              : (model.txCount !== undefined ? String(model.txCount) : "0")
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.subtitleText
                        font.weight: Theme.typography.weightBold
                    }
                }

                // Expand arrow — design's arrow-down-s-fill sits in a 32x32 box but
                // its visible glyph measures 14x7, the same solid 2:1 triangle the
                // design system already ships.
                Item {
                    Layout.preferredWidth: del.chevronWidth
                    Layout.fillHeight: true

                    Image {
                        anchors.centerIn: parent
                        // triangle_down.svg's glyph fills only ~41.7% of its
                        // viewBox, so the image box must be ~2.4x the intended
                        // glyph to land on the design's visible 14x7.
                        width: 34
                        height: 17
                        source: LogosIcons.triangleDown
                        sourceSize.width: 68
                        sourceSize.height: 34
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.55
                        rotation: d.expanded ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation { duration: 120 }
                        }
                    }
                }
            }
        }

        // ---- Expanded details ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: del.rowPadding
            Layout.rightMargin: del.rowPadding
            Layout.bottomMargin: d.expanded ? Theme.spacing.large : 0
            visible: d.expanded
            spacing: Theme.spacing.small

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // Parsed: structured header
            HashRow {
                label: qsTr("Parent block"); value: model.parentBlock || ""; visible: !d.isUnparsed
                onCopyRequested: (t) => del.copyToClipboard(t)
            }
            HashRow {
                label: qsTr("Block root"); value: model.blockRoot || ""; visible: !d.isUnparsed
                onCopyRequested: (t) => del.copyToClipboard(t)
            }
            HashRow {
                label: qsTr("Signature"); value: model.signature || ""; visible: !d.isUnparsed
                onCopyRequested: (t) => del.copyToClipboard(t)
            }

            // Proof of leadership (collapsible sub-group)
            RowLayout {
                Layout.fillWidth: true
                visible: !d.isUnparsed
                spacing: Theme.spacing.small
                LogosText {
                    text: (d.proofExpanded ? "▾ " : "▸ ") + qsTr("Proof of leadership")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                TapHandler { onTapped: d.proofExpanded = !d.proofExpanded }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacing.medium
                visible: !d.isUnparsed && d.proofExpanded
                spacing: Theme.spacing.small
                HashRow { label: qsTr("Leader key"); value: model.leaderKey || ""; onCopyRequested: (t) => del.copyToClipboard(t) }
                HashRow { label: qsTr("Entropy");    value: model.entropy || "";   onCopyRequested: (t) => del.copyToClipboard(t) }
                HashRow { label: qsTr("Proof");      value: model.proof || "";     onCopyRequested: (t) => del.copyToClipboard(t) }
                HashRow { label: qsTr("Voucher cm"); value: model.voucherCm || ""; onCopyRequested: (t) => del.copyToClipboard(t) }
            }

            // Transactions
            LogosText {
                visible: !d.isUnparsed
                text: qsTr("Transactions (%1)").arg(model.txCount || 0)
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: !d.isUnparsed
                spacing: Theme.spacing.small

                Repeater {
                    model: d.expanded ? d.transactionsList : []
                    delegate: TransactionDelegate {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        idx: index
                        json: modelData
                        onCopyToClipboard: (t) => del.copyToClipboard(t)
                    }
                }

                LogosText {
                    visible: (model.txCount || 0) === 0
                    text: qsTr("No transactions in this block.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            // Unparsed: raw fallback
            RowLayout {
                Layout.fillWidth: true
                visible: d.isUnparsed
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Raw payload")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                LogosCopyButton { value: model.rawJson || "" }
            }
            JsonBlock {
                Layout.fillWidth: true
                visible: d.isUnparsed
                json: model.rawJson || qsTr("(no payload)")
            }
        }
    }
}
