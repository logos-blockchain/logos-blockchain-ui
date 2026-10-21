pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Logos.Theme
import Logos.Controls

// Displays typed SQL results and lets the user inspect or copy a complete cell.
ColumnLayout {
    id: root
    property alias model: grid.model
    property string selectedValue: ""

    QtObject {
        id: d

        readonly property int columnWidth: 200
        readonly property int rowHeight: 32
        readonly property int headerHeight: 34
        readonly property int inspectionHeight: 76
    }

    function clearSelection() {
        selectedValue = ""
    }

    HorizontalHeaderView {
        Layout.fillWidth: true
        syncView: grid
        clip: true
        delegate: Rectangle {
            required property var display
            implicitWidth: d.columnWidth
            implicitHeight: d.headerHeight
            color: Theme.palette.surfaceRaised
            border.color: Theme.palette.border
            LogosText {
                anchors.fill: parent
                anchors.margins: Theme.spacing.small
                text: parent.display
                textFormat: Text.PlainText
                font.weight: Theme.typography.weightBold
                elide: Text.ElideRight
            }
        }
    }

    TableView {
        id: grid
        objectName: "resultGrid"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        columnWidthProvider: function(column) { return d.columnWidth }
        rowHeightProvider: function(row) { return d.rowHeight }
        ScrollBar.horizontal: LogosScrollBar {}
        ScrollBar.vertical: LogosScrollBar {}

        delegate: Rectangle {
            required property var display
            required property string valueType
            required property int row
            implicitWidth: d.columnWidth
            implicitHeight: d.rowHeight
            color: row % 2 ? Theme.palette.surfaceRaised : Theme.palette.background
            border.color: Theme.palette.border

            LogosText {
                anchors.fill: parent
                anchors.margins: Theme.spacing.small
                text: parent.display
                textFormat: Text.PlainText
                font.italic: parent.valueType === "null"
                color: parent.valueType === "null" ? Theme.palette.textSecondary : Theme.palette.text
                elide: Text.ElideRight
            }
            TapHandler { onTapped: root.selectedValue = parent.display }
        }
    }

    LogosScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: d.inspectionHeight
        LogosTextArea {
            readOnly: true
            selectByMouse: true
            text: root.selectedValue
            textFormat: TextEdit.PlainText
            placeholderText: qsTr("Select a cell to inspect or copy its full value")
            font.family: Theme.typography.mono
            wrapMode: TextEdit.WrapAnywhere
        }
    }
}
