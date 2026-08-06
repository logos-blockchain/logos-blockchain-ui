import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A boxed, monospace, wrapping JSON/text block. Used for prettified payloads
// and raw fallbacks. The content is selectable with the mouse and copyable
// (Cmd/Ctrl+C), in addition to the dedicated copy buttons elsewhere.
LogosFrame {
    id: root

    property string json: ""

    Layout.fillWidth: true
    padding: Theme.spacing.small
    backgroundColor: Theme.palette.backgroundSecondary

    contentItem: LogosSelectableText {
        id: jsonText
        text: root.json
        persistentSelection: true
        font.pixelSize: Theme.typography.secondaryText
        font.family: Theme.typography.mono
        wrapMode: TextEdit.WrapAnywhere
    }
}
