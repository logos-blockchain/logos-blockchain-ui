import QtQuick
import QtQuick.Controls

Button {
    id: root

    signal copyText()

    implicitWidth: 24
    implicitHeight: 24
    display: AbstractButton.IconOnly
    flat: true

    property string iconSource: "qrc:/icons/copy.svg"

    icon.source: root.iconSource
    icon.width: 24
    icon.height: 24

    function reset() {
        iconSource = "qrc:/icons/copy.svg"
    }

    Timer {
        id: resetTimer
        interval: 1500
        repeat: false
        onTriggered: root.reset()
    }

    onClicked: {
        root.copyText()
        root.iconSource = "qrc:/icons/checkmark.svg"
        resetTimer.restart()
    }
}
