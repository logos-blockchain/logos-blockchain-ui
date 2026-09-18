import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../Units.js" as Units

// Widget for selecting spendable notes (UTXOs) to consume in a channel deposit.
//
// The owner sets `notes` (a JS array of { id, value } parsed from
// wallet_get_notes) and reads back the selection via selectedIds() and the
// selectedCount / selectedTotal properties.
ColumnLayout {
    id: root

    // Array of { id: "<hex>", value: "<u64-string>" }. Assign to (re)populate.
    property var notes: []
    property bool loading: false
    property string errorText: ""
    property bool addressChosen: false

    // Observable selection summary — bindings can't track ListModel reads, so
    // these properties are recomputed explicitly on every selection change.
    property int selectedCount: 0
    // lepta, as a decimal string: a note value can exceed what a double holds
    // exactly — the faucet note is u64::MAX — so the total is never a number.
    property string selectedTotal: "0"

    function selectedIds() {
        var ids = []
        for (var i = 0; i < notesModel.count; ++i) {
            var n = notesModel.get(i)
            if (n.selected)
                ids.push(n.noteId)
        }
        return ids
    }

    function recompute() {
        var c = 0
        var values = []
        for (var i = 0; i < notesModel.count; ++i) {
            var n = notesModel.get(i)
            if (n.selected) {
                c++
                values.push(n.value)
            }
        }
        root.selectedCount = c
        root.selectedTotal = Units.sumLepta(values)
    }

    function clearSelection() {
        for (var i = 0; i < notesModel.count; ++i)
            notesModel.setProperty(i, "selected", false)
        recompute()
    }

    onNotesChanged: {
        notesModel.clear()
        var arr = root.notes || []
        for (var i = 0; i < arr.length; ++i) {
            notesModel.append({
                noteId: String(arr[i].id),
                value: String(arr[i].value),
                selected: false
            })
        }
        recompute()
    }

    spacing: Theme.spacing.small

    ListModel { id: notesModel }

    LogosText {
        Layout.fillWidth: true
        visible: root.loading
        text: qsTr("Loading notes…")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }

    LogosText {
        Layout.fillWidth: true
        visible: !root.loading && root.errorText !== ""
        text: root.errorText
        color: Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosText {
        Layout.fillWidth: true
        visible: !root.loading && root.errorText === "" && notesModel.count === 0
        text: root.addressChosen
              ? qsTr("This account holds no notes to deposit.")
              : qsTr("Choose an account above to load its notes.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosFrame {
        Layout.fillWidth: true
        Layout.preferredHeight: 220
        visible: notesModel.count > 0
        padding: Theme.spacing.small
        backgroundColor: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge

        contentItem: LogosListView {
            id: notesList
            model: notesModel

            delegate: RowLayout {
                width: notesList.width
                spacing: Theme.spacing.small

                LogosCheckbox {
                    checked: model.selected
                    onClicked: {
                        notesModel.setProperty(index, "selected", checked)
                        root.recompute()
                    }
                }

                LogosText {
                    Layout.fillWidth: true
                    text: model.noteId
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.typography.secondaryText
                }

                LogosText {
                    Layout.alignment: Qt.AlignRight
                    text: Units.format(model.value)
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: notesModel.count > 0
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("%1 selected").arg(root.selectedCount)
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosText {
            text: qsTr("Total: %1").arg(Units.format(root.selectedTotal))
            font.pixelSize: Theme.typography.secondaryText
            font.bold: true
        }
    }
}
